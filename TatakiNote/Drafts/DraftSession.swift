import Foundation
import Observation

/// パネルに出している文章の素性。
enum PanelDocument: Equatable {
    case scratch
    case savedDraft(UUID)
    case fromHistory(UUID)
}

/// 文章の切り替え先。
enum DocumentSwitch: Equatable {
    case newScratch
    case draft(UUID)
    case history(UUID)
}

/// 保存の知らせ。
struct DraftSaveEvent: Equatable {
    enum Kind: Equatable {
        case created(UUID)
        case overwritten(UUID)
    }

    let sequence: Int
    let kind: Kind

    /// 保存のトーストを出す知らせか。新しく下書きにしたときだけ。
    var showsToast: Bool {
        switch kind {
        case .created: true
        case .overwritten: false
        }
    }
}

/// パネルの文章と、下書き・履歴との結びつき。
@Observable final class DraftSession {
    private(set) var document: PanelDocument = .scratch
    private(set) var lastSaveEvent: DraftSaveEvent?

    /// 切り替えで書きかけを履歴へ移した回数。
    private(set) var archivedScratchCount = 0

    /// 今の書きかけのモード。
    private(set) var mode: DraftMode

    /// 「新しい書きかけのモード」の設定を読む。
    @ObservationIgnored let newDraftMode: () -> DraftMode

    /// チュートリアルを開いている間、新しい書きかけをインサートで始めるか。
    @ObservationIgnored private(set) var isInsertModeForced = false

    @ObservationIgnored private let panel: PanelModel
    @ObservationIgnored private let library: DraftLibrary
    @ObservationIgnored private let ownProcessIdentifier: pid_t
    @ObservationIgnored private var isReplacingText = false
    @ObservationIgnored private var saveEventSequence = 0
    @ObservationIgnored private var scratchSourceText: String?
    @ObservationIgnored private var viewedHistoryText: String?
    @ObservationIgnored private var insertingDocument: InsertingDocument?

    private struct InsertingDocument {
        let document: PanelDocument
        let text: String
        let scratchSourceText: String?
        let viewedHistoryText: String?
    }

    init(
        panel: PanelModel,
        library: DraftLibrary,
        ownProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        newDraftMode: @escaping () -> DraftMode = { .insert }
    ) {
        self.panel = panel
        self.library = library
        self.ownProcessIdentifier = ownProcessIdentifier
        self.newDraftMode = newDraftMode
        self.mode = newDraftMode()
        panel.onTextChange = { [weak self] text in
            self?.panelTextDidChange(text)
        }
    }

    /// 空白と改行だけの文字列か。
    static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 保存できる本文があるか。
    var isSaveAvailable: Bool {
        !panel.text.isEmpty
    }

    // MARK: - モード

    /// インサートとノートを入れ替える。
    func toggleMode() {
        mode = mode.toggled
    }

    /// 今の書きかけをインサートにする。インサートなら何もしない。
    func switchToInsert() {
        mode = .insert
    }

    /// チュートリアルを開いたとき、今の書きかけをインサートにし、閉じるまで新しい書きかけもインサートで始める。
    func beginInsertModeForTutorial() {
        isInsertModeForced = true
        mode = .insert
    }

    /// チュートリアルを閉じたとき、新しい書きかけを設定どおりに戻す。今の書きかけのモードは変えない。
    func endInsertModeForTutorial() {
        isInsertModeForced = false
    }

    // MARK: - 保存

    /// 今の文章を下書きとして保存する。表示中の下書きなら書き出しを今行う。
    func saveCurrent() {
        guard !panel.text.isEmpty else { return }
        switch document {
        case .scratch, .fromHistory:
            guard let draft = library.addDraft(text: panel.text) else { return }
            document = .savedDraft(draft.id)
            scratchSourceText = nil
            viewedHistoryText = nil
            emitSaveEvent(.created(draft.id))
        case .savedDraft(let id):
            library.flush()
            emitSaveEvent(.overwritten(id))
        }
    }

    // MARK: - 切り替え

    /// 別の文章へすぐ切り替える。書きかけがあれば、切り替える前に挿入していない履歴へ移す。
    func request(_ target: DocumentSwitch) {
        if target == .newScratch {
            resetModeForNewDraft()
        }
        guard !isCurrent(target), let text = targetText(target) else { return }
        library.flush()
        if archiveScratchIfNeeded() {
            archivedScratchCount += 1
        }
        perform(target, text: text)
    }

    /// 終了の前に、書きかけがあれば挿入していない履歴へ移す。
    func prepareForTermination() {
        _ = archiveScratchIfNeeded()
    }

    /// 終了の理由に応じて書きかけを扱う。開き直しなら履歴へ移さずファイルへ残し、書けなければ履歴へ移す。
    @discardableResult
    func prepareForTermination(reason: TerminationReason, store: RelaunchDraftStore) -> TerminationOutcome {
        switch reason {
        case .normal:
            prepareForTermination()
            return .archivedToHistory
        case .relaunch:
            guard let draft = relaunchDraft() else {
                prepareForTermination()
                return .archivedToHistory
            }
            do {
                try store.save(draft)
                return .savedForRelaunch
            } catch {
                prepareForTermination()
                return .archivedToHistory
            }
        }
    }

    // MARK: - 開き直し

    /// 開き直しで残すパネルの書きかけ。本文が空白だけなら `nil`。
    func relaunchDraft() -> RelaunchDraft? {
        guard !Self.isBlank(panel.text) else { return nil }
        let relaunchDocument: RelaunchDraft.Document = switch document {
        case .scratch: .scratch
        case .savedDraft(let id): .savedDraft(id)
        case .fromHistory(let id): .fromHistory(id)
        }
        return RelaunchDraft(
            version: RelaunchDraft.currentVersion,
            text: panel.text,
            document: relaunchDocument,
            mode: mode
        )
    }

    /// 開き直しで残した書きかけをパネルに戻す。本文が空白だけなら何もしない。
    func restore(_ draft: RelaunchDraft) {
        guard !Self.isBlank(draft.text) else { return }
        replacingText {
            switch draft.document {
            case .savedDraft(let id):
                if let saved = library.draft(id: id) {
                    document = .savedDraft(id)
                    viewedHistoryText = nil
                    panel.text = saved.text
                } else {
                    restoreAsScratch(draft.text)
                }
            case .fromHistory(let id):
                if let entry = library.historyEntry(id: id), entry.text == draft.text {
                    document = .fromHistory(id)
                    viewedHistoryText = entry.text
                    panel.text = entry.text
                } else {
                    restoreAsScratch(draft.text)
                }
            case .scratch:
                restoreAsScratch(draft.text)
            }
            scratchSourceText = nil
            mode = draft.mode
        }
    }

    // MARK: - 削除

    /// 下書きを消す。表示中の下書きなら、本文は残して保存していない書きかけにする。
    func deleteDraft(id: UUID) {
        library.deleteDraft(id: id)
        if document == .savedDraft(id) {
            document = .scratch
            scratchSourceText = nil
        }
    }

    /// 履歴の1件を消す。
    func deleteHistoryEntry(id: UUID) {
        library.deleteHistoryEntry(id: id)
    }

    // MARK: - 確定

    /// 確定の計画を作らせ、挿入するなら挿入中の文章を覚えてパネルを空の書きかけにする。
    func prepareCommit(_ makePlan: () -> CommitPlan) -> CommitPlan {
        let documentBefore = document
        let plan = replacingText { makePlan() }
        guard case .insert(let text, _) = plan else { return plan }
        if case .savedDraft = documentBefore {
            library.flush()
        }
        insertingDocument = InsertingDocument(
            document: documentBefore,
            text: text,
            scratchSourceText: scratchSourceText,
            viewedHistoryText: viewedHistoryText
        )
        document = .scratch
        scratchSourceText = nil
        viewedHistoryText = nil
        return plan
    }

    /// 挿入の結果を受けて、履歴に残す・挿入前の文章の扱いに戻す。
    func finishCommit(_ plan: CommitPlan, outcome: CommitOutcome) {
        let inserting = insertingDocument
        insertingDocument = nil
        guard case .insert(let text, let target) = plan else { return }
        switch outcome {
        case .inserted, .insertedIntoSecureField:
            resetModeForNewDraft()
            guard outcome.recordsHistory, !target.isOwnApp(ownProcessIdentifier) else { return }
            library.recordInsertion(text: text, appName: target.localizedName, bundleIdentifier: target.bundleIdentifier)
        case .notInserted, .notConfirmed:
            guard let inserting, panel.text == inserting.text else { return }
            switch inserting.document {
            case .savedDraft(let id):
                if library.draft(id: id) != nil {
                    document = .savedDraft(id)
                }
            case .fromHistory:
                document = inserting.document
                viewedHistoryText = inserting.viewedHistoryText
            case .scratch:
                scratchSourceText = inserting.scratchSourceText
            }
        }
    }

    // MARK: - 内部

    private func resetModeForNewDraft() {
        mode = DraftMode.forNewDraft(setting: newDraftMode(), isInsertForced: isInsertModeForced)
    }

    private func panelTextDidChange(_ text: String) {
        guard !isReplacingText else { return }
        switch document {
        case .savedDraft(let id):
            library.updateDraft(id: id, text: text)
        case .fromHistory:
            document = .scratch
            scratchSourceText = viewedHistoryText
            viewedHistoryText = nil
        case .scratch:
            break
        }
    }

    private func archiveScratchIfNeeded() -> Bool {
        guard document == .scratch,
              !Self.isBlank(panel.text),
              panel.text != scratchSourceText else { return false }
        library.recordUnsentText(panel.text)
        return true
    }

    private func restoreAsScratch(_ text: String) {
        document = .scratch
        viewedHistoryText = nil
        panel.text = text
    }

    private func replacingText<Result>(_ body: () -> Result) -> Result {
        let wasReplacing = isReplacingText
        isReplacingText = true
        defer { isReplacingText = wasReplacing }
        return body()
    }

    private func isCurrent(_ target: DocumentSwitch) -> Bool {
        switch target {
        case .newScratch: document == .scratch && panel.text.isEmpty
        case .draft(let id): document == .savedDraft(id)
        case .history(let id): document == .fromHistory(id)
        }
    }

    private func targetText(_ target: DocumentSwitch) -> String? {
        switch target {
        case .newScratch: ""
        case .draft(let id): library.draft(id: id)?.text
        case .history(let id): library.historyEntry(id: id)?.text
        }
    }

    private func perform(_ target: DocumentSwitch, text: String) {
        replacingText {
            switch target {
            case .newScratch:
                document = .scratch
                viewedHistoryText = nil
            case .draft(let id):
                document = .savedDraft(id)
                viewedHistoryText = nil
            case .history(let id):
                document = .fromHistory(id)
                viewedHistoryText = text
            }
            scratchSourceText = nil
            panel.text = text
        }
    }

    private func emitSaveEvent(_ kind: DraftSaveEvent.Kind) {
        saveEventSequence += 1
        lastSaveEvent = DraftSaveEvent(sequence: saveEventSequence, kind: kind)
    }
}
