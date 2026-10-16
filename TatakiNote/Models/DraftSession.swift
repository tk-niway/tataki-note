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
        ownProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier
    ) {
        self.panel = panel
        self.library = library
        self.ownProcessIdentifier = ownProcessIdentifier
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

    /// 新規作成のアイコンを押せるか。
    var isNewDraftAvailable: Bool {
        !(document == .scratch && panel.text.isEmpty)
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
        case .inserted:
            guard !target.isOwnApp(ownProcessIdentifier) else { return }
            library.recordInsertion(text: text, appName: target.localizedName, bundleIdentifier: target.bundleIdentifier)
        case .notInserted:
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
