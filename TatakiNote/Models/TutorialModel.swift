import Foundation
import Observation

/// チュートリアルの手順。
enum TutorialStep: Int, CaseIterable, Equatable {
    case openPanel
    case writeWithNewline
    case insert
    case nextSteps
}

/// チュートリアルの窓の状態。
@Observable final class TutorialModel {
    private(set) var currentStep: TutorialStep = .openPanel
    private(set) var isShowingSkipNotice = false
    private(set) var isShowingOtherTargetWarning = false
    private(set) var practiceFocusRequest = 0
    private(set) var hotkeyText: String?

    var practiceText: String = "" {
        didSet { practiceTextDidChange() }
    }

    private let ownProcessIdentifier: pid_t
    private let settings: AppSettings
    private let hotkey: () -> PanelShortcut?
    private var newlineBaseline = 0
    private var pendingInsertion: PendingInsertion?

    private struct PendingInsertion {
        var text: String
        var occurrencesBefore: Int
        var sendsAfterInsert: Bool
    }

    init(
        ownProcessIdentifier: pid_t,
        settings: AppSettings,
        hotkey: @escaping () -> PanelShortcut? = { PanelShortcut.currentHotkey() }
    ) {
        self.ownProcessIdentifier = ownProcessIdentifier
        self.settings = settings
        self.hotkey = hotkey
        self.hotkeyText = hotkey()?.displayText
    }

    // MARK: - 手順

    /// 手順が完了しているか(今の手順より前なら真)。
    func isCompleted(_ step: TutorialStep) -> Bool {
        step.rawValue < currentStep.rawValue
    }

    /// 手順1から始め直し、練習用の入力欄・案内・注意・覚えていた状態を空にする。
    func reset() {
        pendingInsertion = nil
        newlineBaseline = 0
        currentStep = .openPanel
        isShowingSkipNotice = false
        isShowingOtherTargetWarning = false
        practiceText = ""
    }

    /// 「スキップ」の案内を出す。
    func skip() {
        isShowingSkipNotice = true
    }

    /// 練習用の入力欄へのフォーカスを要求する。
    func requestPracticeFocus() {
        practiceFocusRequest += 1
    }

    /// 「スキップ」の代わりに「完了」を出すか。
    var showsFinishButton: Bool {
        currentStep == .nextSteps
    }

    // MARK: - パネルと挿入の観測

    /// パネルの表示・挿入先・文章が変わったことを受けて、手順を進める。
    func panelDidChange(isPresented: Bool, target: InsertionTarget?, text: String) {
        guard isPresented, let target else { return }
        let isOwnTarget = target.processIdentifier == ownProcessIdentifier
        if currentStep != .nextSteps {
            isShowingOtherTargetWarning = !isOwnTarget
        }
        guard isOwnTarget else { return }
        switch currentStep {
        case .openPanel:
            newlineBaseline = Self.newlineCount(in: text)
            currentStep = .writeWithNewline
        case .writeWithNewline:
            if Self.newlineCount(in: text) > newlineBaseline {
                currentStep = .insert
            }
        case .insert, .nextSteps:
            break
        }
    }

    /// 練習用の入力欄への挿入が要求されたことを覚える(手順3の間だけ)。
    func insertionRequested(text: String, target: InsertionTarget, sendsAfterInsert: Bool) {
        guard currentStep == .insert,
              target.processIdentifier == ownProcessIdentifier,
              !text.isEmpty
        else { return }
        pendingInsertion = PendingInsertion(
            text: text,
            occurrencesBefore: Self.occurrences(of: text, in: practiceText),
            sendsAfterInsert: sendsAfterInsert
        )
    }

    // MARK: - キーの表示

    /// 今の確定キーの表示(未設定なら `nil`)。
    var commitKeyText: String? {
        settings.commitKey?.displayText
    }

    /// 今の確定+送信キーの表示(未設定なら `nil`)。
    var commitAndSendKeyText: String? {
        settings.commitAndSendKey?.displayText
    }

    /// 手順1の説明の文。
    var openPanelInstruction: String {
        guard let hotkeyText else {
            return String(localized: "ホットキーが設定されていません。設定の「一般」で設定するか、メニューバーの「パネルを開く」で開きます。")
        }
        return String(localized: "まず下の練習用の入力欄をクリックします。それから \(hotkeyText) を押します。")
    }

    /// 手順3の説明の文。
    var insertInstruction: String {
        guard let commitKeyText else {
            return String(localized: "確定キーが設定されていません。設定の「一般」で設定してください。")
        }
        return String(localized: "\(commitKeyText) で確定すると、練習用の入力欄に文章が入ります。")
    }

    /// 手順4の確定+送信の紹介の文。
    var commitAndSendIntroduction: String {
        guard let commitAndSendKeyText else {
            return String(localized: "挿入してそのまま送信するキーを、設定の「一般」で設定できます。")
        }
        return String(localized: "\(commitAndSendKeyText) で、挿入してそのまま送信できます。")
    }

    /// ホットキーの表示を今の設定から読み直す。
    func refreshKeys() {
        hotkeyText = hotkey()?.displayText
    }

    // MARK: - 内部

    private func practiceTextDidChange() {
        guard currentStep == .insert, let pendingInsertion else { return }
        if Self.occurrences(of: pendingInsertion.text, in: practiceText) > pendingInsertion.occurrencesBefore {
            self.pendingInsertion = nil
            isShowingOtherTargetWarning = false
            currentStep = .nextSteps
        }
    }

    private static func newlineCount(in text: String) -> Int {
        text.unicodeScalars.filter { $0 == "\n" }.count
    }

    private static func occurrences(of target: String, in text: String) -> Int {
        guard !target.isEmpty else { return 0 }
        return text.components(separatedBy: target).count - 1
    }
}
