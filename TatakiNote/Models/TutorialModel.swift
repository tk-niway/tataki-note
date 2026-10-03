import Foundation
import Observation

/// チュートリアルの手順。
enum TutorialStep: Int, CaseIterable, Equatable {
    case openPanel
    case writeWithNewline
    case send
    case nextSteps
}

/// 手順4で紹介する使い方。
enum TutorialNextStepIntroduction: CaseIterable {
    case hotkeyChange
    case draftKept

    var heading: String {
        switch self {
        case .hotkeyChange: String(localized: "ホットキーの変更")
        case .draftKept: String(localized: "下書き")
        }
    }

    var text: String {
        switch self {
        case .hotkeyChange:
            String(localized: "設定の「キー」の「パネルを開く・閉じる」で変えられます。")
        case .draftKept:
            String(localized: "esc でパネルを閉じても、書いた文章は下書きとして残ります。次に開くと続きから書けます。")
        }
    }
}

/// チュートリアルの窓の状態。
@Observable final class TutorialModel {
    private(set) var currentStep: TutorialStep = .openPanel
    private(set) var isShowingSkipNotice = false
    private(set) var isShowingOtherTargetWarning = false
    private(set) var practiceFocusRequest = 0
    private(set) var hotkeyText: String?
    private(set) var chat = PracticeChat()

    var practiceText: String = ""

    private let ownProcessIdentifier: pid_t
    private let settings: AppSettings
    private let hotkey: () -> PanelShortcut?
    private var newlineBaseline = 0
    private var pendingInsertion: PendingInsertion?

    private struct PendingInsertion {
        var text: String
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

    /// 手順1から始め直し、練習用のチャット・入力欄・案内・注意・覚えていた状態を元に戻す。
    func reset() {
        pendingInsertion = nil
        newlineBaseline = 0
        chat = PracticeChat()
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
        let isOwnTarget = target.isOwnApp(ownProcessIdentifier)
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
                currentStep = .send
            }
        case .send, .nextSteps:
            break
        }
    }

    /// 練習用のチャットへの挿入が要求されたことを覚える。
    func insertionRequested(text: String, target: InsertionTarget, sendsAfterInsert: Bool) {
        guard target.isOwnApp(ownProcessIdentifier), !text.isEmpty else { return }
        pendingInsertion = PendingInsertion(text: text, sendsAfterInsert: sendsAfterInsert)
    }

    /// 練習用のチャットに文章を送る。空なら何もせず `false` を返す。
    @discardableResult
    func sendPracticeMessage(_ text: String) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let route = sendRoute(for: text)
        pendingInsertion = nil
        let reply = PracticeChatReply.text(
            for: route,
            commitAndSendKey: commitAndSendKeyText,
            hotkey: hotkeyText
        )
        chat.appendSent(text, reply: reply, route: route)
        practiceText = ""
        if currentStep == .send, route != .direct {
            isShowingOtherTargetWarning = false
            currentStep = .nextSteps
        }
        return true
    }

    // MARK: - キーの表示

    /// 今の確定+挿入キーの表示(未設定なら `nil`)。
    var commitKeyText: String? {
        settings.commitKey?.displayText
    }

    /// 今の確定+送信キーの表示(未設定なら `nil`)。
    var commitAndSendKeyText: String? {
        settings.commitAndSendKey?.displayText
    }

    /// 窓の冒頭の文。
    static var introduction: String {
        String(localized: "AI チャットの入力欄では、変換の確定や改行のつもりの Enter で、書きかけのまま送られてしまうことがあります。下の練習用のチャットで、パネルで書いて送るまでを1段階ずつ試してみましょう。")
    }

    /// 挿入先が別のアプリのときの注意の文。
    static var otherTargetWarning: String {
        String(localized: "パネルの挿入先が別のアプリになっています。このまま確定すると、練習の文章がそのアプリに入り、確定+送信キーでは送信もされます。esc でパネルを閉じ、練習用のチャットの入力欄をクリックしてから開き直してください。")
    }

    /// 手順1の説明の文。
    var openPanelInstruction: String {
        guard let hotkeyText else {
            return String(localized: "ホットキーが設定されていません。設定の「キー」で設定するか、メニューバーの「パネルを開く」で開きます。")
        }
        return String(localized: "まず下の練習用のチャットの入力欄をクリックします。それから \(hotkeyText) を押します。")
    }

    /// 手順2の説明の文。
    var writeInstruction: String {
        String(localized: "パネルの中では、変換の確定にも改行にも Enter を使えます。Enter で送信されることはありません。2行以上の文章を書いてみましょう。")
    }

    /// 手順3の説明の文。
    var sendInstruction: String {
        if let commitAndSendKeyText {
            return String(localized: "パネルで \(commitAndSendKeyText) を押すと、書いた文章が練習用のチャットに入り、そのまま送信されます。")
        }
        if let commitKeyText {
            return String(localized: "パネルで \(commitKeyText) を押すと、書いた文章が練習用のチャットの入力欄に入ります。内容を確かめてから ↩ を押して送信しましょう。")
        }
        return String(localized: "確定+挿入キーも確定+送信キーも登録されていません。設定の「キー」で登録してください。")
    }

    /// ホットキーの表示を今の設定から読み直す。
    func refreshKeys() {
        hotkeyText = hotkey()?.displayText
    }

    // MARK: - 内部

    private func sendRoute(for text: String) -> PracticeChatSendRoute {
        guard let pendingInsertion, text.contains(pendingInsertion.text) else { return .direct }
        return pendingInsertion.sendsAfterInsert ? .commitAndSend : .commitThenReturn
    }

    private static func newlineCount(in text: String) -> Int {
        text.unicodeScalars.filter { $0 == "\n" }.count
    }
}
