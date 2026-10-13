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

/// 保存していない文章の確認での選び方。
enum UnsavedTextChoice {
    case save
    case discard
    case cancel
}

/// 保存の知らせ。
struct DraftSaveEvent: Equatable {
    enum Kind: Equatable {
        case created(UUID)
        case overwritten(UUID)
    }

    /// どの操作で保存したか。
    enum Origin: Equatable {
        /// ⌘S・保存ボタン。
        case saveCommand
        /// 保存していない文章の確認の「保存」。
        case confirmation
    }

    let sequence: Int
    let kind: Kind
    let origin: Origin

    init(sequence: Int, kind: Kind, origin: Origin = .saveCommand) {
        self.sequence = sequence
        self.kind = kind
        self.origin = origin
    }
}

/// パネルの文章と、下書き・履歴との結びつき。
@Observable final class DraftSession {
    private(set) var document: PanelDocument = .scratch
    private(set) var pendingSwitch: DocumentSwitch? {
        didSet {
            guard pendingSwitch != oldValue else { return }
            confirmationFocus = pendingSwitch == nil ? nil : (isKeyboardNavigationEnabled() ? .save : nil)
        }
    }
    private(set) var lastSaveEvent: DraftSaveEvent?

    /// 確認で、キーボードで選んでいるボタン。確認が無いときと、キーボードナビゲーションがオフのときは nil。
    private(set) var confirmationFocus: UnsavedTextChoice?

    /// 確認のボタンの、Tab で進む順。
    static let confirmationFocusOrder: [UnsavedTextChoice] = [.discard, .cancel, .save]

    @ObservationIgnored private let panel: PanelModel
    @ObservationIgnored private let library: DraftLibrary
    @ObservationIgnored private let ownProcessIdentifier: pid_t
    @ObservationIgnored private let isKeyboardNavigationEnabled: () -> Bool
    @ObservationIgnored private var isReplacingText = false
    @ObservationIgnored private var saveEventSequence = 0
    @ObservationIgnored private var insertingDocument: (document: PanelDocument, text: String)?

    init(
        panel: PanelModel,
        library: DraftLibrary,
        ownProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        isKeyboardNavigationEnabled: @escaping () -> Bool = { false }
    ) {
        self.panel = panel
        self.library = library
        self.ownProcessIdentifier = ownProcessIdentifier
        self.isKeyboardNavigationEnabled = isKeyboardNavigationEnabled
        panel.onTextChange = { [weak self] text in
            self?.panelTextDidChange(text)
        }
    }

    /// 保存していない文章がパネルにあるか。
    var hasUnsavedText: Bool {
        if case .savedDraft = document { return false }
        return !panel.text.isEmpty
    }

    /// 保存できる本文があるか。
    var isSaveAvailable: Bool {
        !panel.text.isEmpty
    }

    /// 保存のアイコンを押せるか。確認の重ね表示が出ている間だけ押せない。
    var isSaveButtonEnabled: Bool {
        pendingSwitch == nil
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
            emitSaveEvent(.created(draft.id))
        case .savedDraft(let id):
            library.flush()
            emitSaveEvent(.overwritten(id))
        }
    }

    // MARK: - 切り替え

    /// 別の文章への切り替えを求める。保存していない文章があれば確認を立てる。
    func request(_ target: DocumentSwitch) {
        guard !isCurrent(target), exists(target) else { return }
        if hasUnsavedText {
            pendingSwitch = target
            return
        }
        library.flush()
        perform(target)
    }

    /// 切り替えの確認への答えを受けて切り替える。
    func resolvePendingSwitch(_ choice: UnsavedTextChoice) {
        guard let target = pendingSwitch else { return }
        switch choice {
        case .save:
            if let draft = library.addDraft(text: panel.text) {
                document = .savedDraft(draft.id)
                emitSaveEvent(.created(draft.id), origin: .confirmation)
            }
            library.flush()
            perform(target)
        case .discard:
            library.flush()
            perform(target)
        case .cancel:
            pendingSwitch = nil
        }
    }

    /// 選んでいるボタンを、Tab で進む順に offset だけ動かす。端では反対の端へ回る。選んでいるボタンが無ければ何もしない。
    func moveConfirmationFocus(by offset: Int) {
        let order = Self.confirmationFocusOrder
        guard let focus = confirmationFocus, let index = order.firstIndex(of: focus) else { return }
        let count = order.count
        confirmationFocus = order[((index + offset) % count + count) % count]
    }

    /// 選んでいるボタンで確認に答える。選んでいるボタンが無ければ何もしない。
    func resolveFocusedConfirmation() {
        guard let focus = confirmationFocus else { return }
        resolvePendingSwitch(focus)
    }

    // MARK: - 削除

    /// 下書きを消す。表示中の下書きなら、本文は残して保存していない書きかけにする。
    func deleteDraft(id: UUID) {
        library.deleteDraft(id: id)
        if document == .savedDraft(id) {
            document = .scratch
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
        insertingDocument = (document: documentBefore, text: text)
        document = .scratch
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
            case .scratch:
                break
            }
        }
    }

    // MARK: - 内部

    private func panelTextDidChange(_ text: String) {
        guard !isReplacingText, case .savedDraft(let id) = document else { return }
        library.updateDraft(id: id, text: text)
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
        case .history: false
        }
    }

    private func exists(_ target: DocumentSwitch) -> Bool {
        switch target {
        case .newScratch: true
        case .draft(let id): library.draft(id: id) != nil
        case .history(let id): library.historyEntry(id: id) != nil
        }
    }

    private func perform(_ target: DocumentSwitch) {
        pendingSwitch = nil
        guard exists(target) else { return }
        replacingText {
            switch target {
            case .newScratch:
                document = .scratch
                panel.text = ""
            case .draft(let id):
                guard let draft = library.draft(id: id) else { return }
                document = .savedDraft(id)
                panel.text = draft.text
            case .history(let id):
                guard let entry = library.historyEntry(id: id) else { return }
                document = .fromHistory(id)
                panel.text = entry.text
            }
        }
        panel.requestFocus()
    }

    private func emitSaveEvent(_ kind: DraftSaveEvent.Kind, origin: DraftSaveEvent.Origin = .saveCommand) {
        saveEventSequence += 1
        lastSaveEvent = DraftSaveEvent(sequence: saveEventSequence, kind: kind, origin: origin)
    }
}
