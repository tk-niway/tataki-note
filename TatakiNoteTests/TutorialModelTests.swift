import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct TutorialModelTests {
    private static let ownPid: pid_t = 4242
    private let own = InsertionTarget(processIdentifier: TutorialModelTests.ownPid, bundleIdentifier: "com.example.TatakiNote", localizedName: "TatakiNote")
    private let other = InsertionTarget(processIdentifier: pid_t.max - 1, bundleIdentifier: "com.example.Other", localizedName: "Other")
    private let hotkey = PanelShortcut(keyCode: 49, modifiers: [.option, .shift])

    private final class HotkeyBox {
        var value: PanelShortcut?

        init(_ value: PanelShortcut?) {
            self.value = value
        }
    }

    private func withModel(
        hotkey: PanelShortcut?? = nil,
        _ body: (TutorialModel, AppSettings, HotkeyBox) throws -> Void
    ) throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.commitKey = nil
        settings.commitAndSendKey = nil
        let box = HotkeyBox(hotkey ?? self.hotkey)
        let model = TutorialModel(ownProcessIdentifier: Self.ownPid, settings: settings, hotkey: { box.value })
        try body(model, settings, box)
    }

    private func moveToWriteStep(_ model: TutorialModel, text: String = "") {
        model.panelDidChange(isPresented: true, target: own, text: text)
    }

    private func moveToSendStep(_ model: TutorialModel) {
        moveToWriteStep(model)
        model.panelDidChange(isPresented: true, target: own, text: "a\nb")
    }

    private func moveToNextStepsStep(_ model: TutorialModel) {
        moveToSendStep(model)
        model.insertionRequested(text: "a\nb", target: own, sendsAfterInsert: true)
        model.sendPracticeMessage("a\nb")
    }

    // MARK: - 手順1

    @Test("自分自身が挿入先のパネルが開くと手順1が完了して手順2に進む")
    func openingPanelForOwnTargetCompletesStepOne() throws {
        try withModel { model, _, _ in
            #expect(model.currentStep == .openPanel)
            #expect(!model.isCompleted(.openPanel))

            model.panelDidChange(isPresented: true, target: own, text: "")

            #expect(model.currentStep == .writeWithNewline)
            #expect(model.isCompleted(.openPanel))
            #expect(!model.isCompleted(.writeWithNewline))
            #expect(!model.isShowingOtherTargetWarning)
        }
    }

    @Test("他のアプリが挿入先のパネルが開いても進まない")
    func openingPanelForOtherTargetDoesNotAdvance() throws {
        try withModel { model, _, _ in
            model.panelDidChange(isPresented: true, target: other, text: "")

            #expect(model.currentStep == .openPanel)
            #expect(!model.isCompleted(.openPanel))
        }
    }

    @Test("パネルが閉じている通知や挿入先が無い通知では進まず、注意も出ない")
    func closedPanelOrMissingTargetDoesNothing() throws {
        try withModel { model, _, _ in
            model.panelDidChange(isPresented: false, target: own, text: "")
            model.panelDidChange(isPresented: true, target: nil, text: "")

            #expect(model.currentStep == .openPanel)
            #expect(!model.isShowingOtherTargetWarning)
        }
    }

    // MARK: - 挿入先の注意(AC-21)

    @Test("AC-21: 他のアプリが挿入先のパネルが開くと注意が出て、自分自身が挿入先になると消える")
    func warningShowsForOtherTargetAndClearsForOwn() throws {
        try withModel { model, _, _ in
            model.panelDidChange(isPresented: true, target: other, text: "")
            #expect(model.isShowingOtherTargetWarning)

            model.panelDidChange(isPresented: true, target: own, text: "")

            #expect(!model.isShowingOtherTargetWarning)
            #expect(model.currentStep == .writeWithNewline)
        }
    }

    @Test("AC-21: 手順2・3の間も注意が出るが、手順4では出ない")
    func warningShowsDuringStepsOneToThreeOnly() throws {
        try withModel { model, _, _ in
            moveToWriteStep(model)
            model.panelDidChange(isPresented: true, target: other, text: "")
            #expect(model.currentStep == .writeWithNewline)
            #expect(model.isShowingOtherTargetWarning)

            model.panelDidChange(isPresented: true, target: own, text: "a\nb")
            #expect(model.currentStep == .send)
            #expect(!model.isShowingOtherTargetWarning)
            model.panelDidChange(isPresented: true, target: other, text: "a\nb")
            #expect(model.currentStep == .send)
            #expect(model.isShowingOtherTargetWarning)

            model.panelDidChange(isPresented: true, target: own, text: "a\nb")
            model.insertionRequested(text: "a\nb", target: own, sendsAfterInsert: true)
            model.sendPracticeMessage("a\nb")
            #expect(model.currentStep == .nextSteps)
            #expect(!model.isShowingOtherTargetWarning)

            model.panelDidChange(isPresented: true, target: other, text: "")
            #expect(!model.isShowingOtherTargetWarning)
        }
    }

    @Test("AC-21: 注意の文は、練習の文章がそのアプリに入り送信もされうることと、esc で閉じて入力欄をクリックしてから開き直すことを伝える")
    func otherTargetWarningText() {
        let text = TutorialModel.otherTargetWarning

        #expect(text.contains("そのアプリに入り"))
        #expect(text.contains("送信"))
        #expect(text.contains("esc"))
        #expect(text.contains("クリック"))
        #expect(text.contains("開き直"))
    }

    // MARK: - 手順2

    @Test("手順2に入った後にパネルの文章の改行が増えると手順3に進む")
    func addingNewlineCompletesStepTwo() throws {
        try withModel { model, _, _ in
            moveToWriteStep(model)

            model.panelDidChange(isPresented: true, target: own, text: "abc\ndef")

            #expect(model.currentStep == .send)
            #expect(model.isCompleted(.writeWithNewline))
        }
    }

    @Test("改行の無い入力では手順2が進まない")
    func typingWithoutNewlineDoesNotComplete() throws {
        try withModel { model, _, _ in
            moveToWriteStep(model)

            model.panelDidChange(isPresented: true, target: own, text: "abc")
            model.panelDidChange(isPresented: true, target: own, text: "abcdef")

            #expect(model.currentStep == .writeWithNewline)
            #expect(!model.isCompleted(.writeWithNewline))
        }
    }

    @Test("手順2に入る前からあった改行では進まず、そこから増えると進む")
    func newlinesBeforeStepTwoDoNotCount() throws {
        try withModel { model, _, _ in
            model.panelDidChange(isPresented: true, target: own, text: "draft\nwith\nlines")
            #expect(model.currentStep == .writeWithNewline)

            model.panelDidChange(isPresented: true, target: own, text: "draft\nwith\nlines")
            model.panelDidChange(isPresented: true, target: own, text: "draft\nwith\nlines!")
            #expect(model.currentStep == .writeWithNewline)

            model.panelDidChange(isPresented: true, target: own, text: "draft\nwith\nlines\n")
            #expect(model.currentStep == .send)
        }
    }

    @Test("他のアプリが挿入先のパネルの改行では手順2が進まない")
    func newlineForOtherTargetDoesNotComplete() throws {
        try withModel { model, _, _ in
            moveToWriteStep(model)

            model.panelDidChange(isPresented: true, target: other, text: "abc\ndef")

            #expect(model.currentStep == .writeWithNewline)
        }
    }

    @Test("AC-18: 手順2の説明は、パネルの中なら Enter を変換の確定にも改行にも使え、送信されないことを伝える")
    func writeInstructionExplainsEnter() throws {
        try withModel { model, _, _ in
            let text = model.writeInstruction

            #expect(text.contains("変換の確定"))
            #expect(text.contains("改行"))
            #expect(text.contains("送信されることはありません"))
        }
    }

    // MARK: - 練習用のチャットの初期状態(AC-6)

    @Test("AC-6: 作った直後の練習用のチャットは例の吹き出しだけで、入力欄は空")
    func initialChatHasOnlyExample() throws {
        try withModel { model, _, _ in
            #expect(model.chat.messages.count == 1)
            #expect(model.chat.messages[0].kind == .example)
            #expect(model.practiceText.isEmpty)
        }
    }

    // MARK: - 送信(AC-7, AC-8)

    @Test("AC-7: 送ると、送った文章がそのまま自分の吹き出しに並び、入力欄が空になり、続けて返事の吹き出しが出る")
    func sendAppendsSentAndReplyAndClearsInput() throws {
        try withModel { model, _, _ in
            model.practiceText = " hello\nworld "

            let didSend = model.sendPracticeMessage(" hello\nworld ")

            #expect(didSend)
            #expect(model.chat.messages.count == 3)
            #expect(model.chat.messages[1].kind == .sent)
            #expect(model.chat.messages[1].text == " hello\nworld ")
            if case .reply = model.chat.messages[2].kind {} else {
                Issue.record("末尾が返事の吹き出しではない")
            }
            #expect(!model.chat.messages[2].text.isEmpty)
            #expect(model.practiceText.isEmpty)
        }
    }

    @Test("AC-8: 空・空白と改行だけの文章を送っても、吹き出しも返事も増えず、入力欄もそのまま")
    func sendingBlankDoesNothing() throws {
        try withModel { model, _, _ in
            let before = model.chat

            for blank in ["", "   ", "\n", " \n\t \n"] {
                model.practiceText = blank
                let didSend = model.sendPracticeMessage(blank)

                #expect(!didSend)
                #expect(model.chat == before)
                #expect(model.practiceText == blank)
            }
        }
    }

    // MARK: - 手順3(AC-14)

    @Test("AC-14: 確定+送信キーで入って送られると手順4に進み、返事は確定+送信の経路になる")
    func commitAndSendCompletesStepThree() throws {
        try withModel { model, _, _ in
            moveToSendStep(model)
            model.panelDidChange(isPresented: true, target: other, text: "")
            #expect(model.isShowingOtherTargetWarning)

            model.insertionRequested(text: "abc\ndef", target: own, sendsAfterInsert: true)
            model.sendPracticeMessage("abc\ndef")

            #expect(model.currentStep == .nextSteps)
            #expect(model.isCompleted(.send))
            #expect(!model.isShowingOtherTargetWarning)
            #expect(model.chat.messages.last?.kind == .reply(.commitAndSend))
        }
    }

    @Test("AC-14: 確定キーで入れただけ(まだ送っていない)では進まず、自分で送ると手順4に進む")
    func commitThenReturnCompletesStepThreeOnlyWhenSent() throws {
        try withModel { model, _, _ in
            moveToSendStep(model)

            model.insertionRequested(text: "abc\ndef", target: own, sendsAfterInsert: false)
            model.practiceText = "abc\ndef"
            #expect(model.currentStep == .send)
            #expect(model.chat.messages.count == 1)

            model.sendPracticeMessage(model.practiceText)

            #expect(model.currentStep == .nextSteps)
            #expect(model.chat.messages.last?.kind == .reply(.commitThenReturn))
        }
    }

    @Test("AC-14: 入れた文章を含めて送れば、前後に書き足していても挿入の経路として扱う")
    func sendContainingInsertedTextCountsAsInsertion() throws {
        try withModel { model, _, _ in
            moveToSendStep(model)
            model.insertionRequested(text: "abc", target: own, sendsAfterInsert: false)

            model.sendPracticeMessage("hello abc!")

            #expect(model.currentStep == .nextSteps)
            #expect(model.chat.messages.last?.kind == .reply(.commitThenReturn))
        }
    }

    @Test("AC-14: 入れた文章を書き換えて含まなくなった送信は、直接の送信として扱い手順は進まない")
    func sendWithoutInsertedTextIsDirect() throws {
        try withModel { model, _, _ in
            moveToSendStep(model)
            model.insertionRequested(text: "abc", target: own, sendsAfterInsert: true)

            model.sendPracticeMessage("xyz")

            #expect(model.currentStep == .send)
            #expect(model.chat.messages.last?.kind == .reply(.direct))
        }
    }

    // MARK: - 手順の進まない送信(AC-11, AC-15)

    @Test("AC-11: 直接書いて送ると、どの手順でも手順は進まず、パネルで書くよう促す返事が出る")
    func directSendNeverAdvances() throws {
        try withModel { model, _, _ in
            model.sendPracticeMessage("hello")
            #expect(model.currentStep == .openPanel)

            moveToWriteStep(model)
            model.sendPracticeMessage("hello")
            #expect(model.currentStep == .writeWithNewline)

            model.panelDidChange(isPresented: true, target: own, text: "a\nb")
            model.sendPracticeMessage("hello")
            #expect(model.currentStep == .send)

            #expect(model.chat.messages.last?.kind == .reply(.direct))
            #expect(model.chat.messages.last?.text.contains(hotkey.displayText) == true)
        }
    }

    @Test("AC-11: 直接書いて送ったときにホットキーが無ければ、メニューバーの「パネルを開く」を案内する")
    func directReplyWithoutHotkey() throws {
        try withModel(hotkey: .some(nil)) { model, _, _ in
            model.sendPracticeMessage("hello")

            let reply = try #require(model.chat.messages.last)
            #expect(reply.kind == .reply(.direct))
            #expect(reply.text.contains("メニューバー"))
            #expect(reply.text.contains("パネルを開く"))
        }
    }

    @Test("AC-15: 手順1・2の間は、パネルで入れた文章を送っても手順は進まない")
    func insertionSendBeforeStepThreeDoesNotAdvance() throws {
        try withModel { model, _, _ in
            model.insertionRequested(text: "early", target: own, sendsAfterInsert: true)
            model.sendPracticeMessage("early")
            #expect(model.currentStep == .openPanel)
            #expect(model.chat.messages.last?.kind == .reply(.commitAndSend))

            moveToWriteStep(model)
            model.insertionRequested(text: "early two", target: own, sendsAfterInsert: false)
            model.sendPracticeMessage("early two")
            #expect(model.currentStep == .writeWithNewline)
            #expect(model.chat.messages.last?.kind == .reply(.commitThenReturn))
        }
    }

    @Test("AC-15: 手順4でも送ることができ、返事は経路で変わる")
    func sendingInStepFourDependsOnRoute() throws {
        try withModel { model, settings, _ in
            settings.commitAndSendKey = .commandReturn
            moveToNextStepsStep(model)
            let messageCount = model.chat.messages.count

            model.sendPracticeMessage("direct")
            let directReply = try #require(model.chat.messages.last)
            model.insertionRequested(text: "via panel", target: own, sendsAfterInsert: false)
            model.sendPracticeMessage("via panel")
            let panelReply = try #require(model.chat.messages.last)

            #expect(model.currentStep == .nextSteps)
            #expect(model.chat.messages.count == messageCount + 4)
            #expect(directReply.kind == .reply(.direct))
            #expect(panelReply.kind == .reply(.commitThenReturn))
            #expect(directReply.text != panelReply.text)
        }
    }

    // MARK: - 覚える挿入(AC-16)

    @Test("AC-16: 他のアプリへの挿入の要求は覚えず、その後の送信は直接の送信として扱う")
    func insertionForOtherTargetIsIgnored() throws {
        try withModel { model, _, _ in
            moveToSendStep(model)

            model.insertionRequested(text: "abc", target: other, sendsAfterInsert: true)
            model.sendPracticeMessage("abc")

            #expect(model.currentStep == .send)
            #expect(model.chat.messages.last?.kind == .reply(.direct))
        }
    }

    @Test("AC-16: 空の文章の挿入の要求は覚えない")
    func emptyInsertionIsIgnored() throws {
        try withModel { model, _, _ in
            moveToSendStep(model)

            model.insertionRequested(text: "", target: own, sendsAfterInsert: true)
            model.sendPracticeMessage("abc")

            #expect(model.currentStep == .send)
            #expect(model.chat.messages.last?.kind == .reply(.direct))
        }
    }

    @Test("AC-16: 覚えた挿入は1回の送信で捨て、次の送信には使わない")
    func pendingInsertionIsDiscardedAfterOneSend() throws {
        try withModel { model, _, _ in
            moveToNextStepsStep(model)
            model.insertionRequested(text: "abc", target: own, sendsAfterInsert: true)

            model.sendPracticeMessage("abc")
            model.sendPracticeMessage("abc")

            let replies = model.chat.messages.compactMap { message -> PracticeChatSendRoute? in
                if case .reply(let route) = message.kind { return route }
                return nil
            }
            #expect(replies.suffix(2) == [.commitAndSend, .direct])
        }
    }

    @Test("AC-16: 空の文章の送信は、覚えた挿入を捨てない")
    func blankSendKeepsPendingInsertion() throws {
        try withModel { model, _, _ in
            moveToSendStep(model)
            model.insertionRequested(text: "abc", target: own, sendsAfterInsert: false)

            model.sendPracticeMessage("  ")
            model.sendPracticeMessage("abc")

            #expect(model.currentStep == .nextSteps)
            #expect(model.chat.messages.last?.kind == .reply(.commitThenReturn))
        }
    }

    // MARK: - キーの表示(AC-17)

    @Test("手順1の文に今のホットキーの表示が入る")
    func openPanelInstructionContainsHotkey() throws {
        try withModel { model, _, _ in
            #expect(model.hotkeyText == hotkey.displayText)
            #expect(model.openPanelInstruction.contains(hotkey.displayText))
            #expect(model.openPanelInstruction.contains("クリック"))
        }
    }

    @Test("ホットキーが未設定なら、設定の「一般」とメニューバーで開くよう案内する")
    func openPanelInstructionWithoutHotkey() throws {
        try withModel(hotkey: .some(nil)) { model, _, _ in
            #expect(model.hotkeyText == nil)
            #expect(model.openPanelInstruction.contains("ホットキーが設定されていません"))
            #expect(model.openPanelInstruction.contains("設定の「一般」"))
            #expect(model.openPanelInstruction.contains("パネルを開く"))
        }
    }

    @Test("ホットキーを変えて読み直すと手順1の文も変わる")
    func refreshKeysUpdatesHotkeyText() throws {
        try withModel { model, _, box in
            let before = model.openPanelInstruction
            let changed = PanelShortcut(keyCode: 40, modifiers: [.command, .control])
            box.value = changed

            #expect(model.openPanelInstruction == before)
            model.refreshKeys()

            #expect(model.hotkeyText == changed.displayText)
            #expect(model.openPanelInstruction != before)
            #expect(model.openPanelInstruction.contains(changed.displayText))

            box.value = nil
            model.refreshKeys()
            #expect(model.hotkeyText == nil)
        }
    }

    @Test("AC-17: 確定+送信キーがあれば、そのキーだけを示し、確定キーもあっても示さない")
    func sendInstructionShowsOnlyCommitAndSendKey() throws {
        try withModel { model, settings, _ in
            settings.commitKey = .commandShiftReturn
            settings.commitAndSendKey = .commandReturn

            let text = model.sendInstruction

            #expect(model.commitAndSendKeyText == PanelShortcut.commandReturn.displayText)
            #expect(text.contains(PanelShortcut.commandReturn.displayText))
            #expect(!text.contains(PanelShortcut.commandShiftReturn.displayText))
            #expect(!text.contains("設定の「一般」"))
        }
    }

    @Test("AC-17: 確定+送信キーが無く確定キーだけあれば、確定キーで入れてから ↩ で送るよう示す")
    func sendInstructionWithCommitKeyOnly() throws {
        try withModel { model, settings, _ in
            settings.commitKey = .commandShiftReturn
            settings.commitAndSendKey = nil

            let text = model.sendInstruction

            #expect(model.commitKeyText == PanelShortcut.commandShiftReturn.displayText)
            #expect(text.contains(PanelShortcut.commandShiftReturn.displayText))
            #expect(text.contains("↩"))
            #expect(!text.contains("設定の「一般」"))
        }
    }

    @Test("AC-17: どちらも無いときだけ、設定の「一般」で登録するよう示す")
    func sendInstructionWithoutKeys() throws {
        try withModel { model, settings, _ in
            settings.commitKey = nil
            settings.commitAndSendKey = nil

            let text = model.sendInstruction

            #expect(model.commitKeyText == nil)
            #expect(model.commitAndSendKeyText == nil)
            #expect(text.contains("設定の「一般」"))
            #expect(text.contains("登録"))
        }
    }

    @Test("AC-17: 設定でキーを変えると案内も変わる")
    func sendInstructionFollowsSettings() throws {
        try withModel { model, settings, _ in
            settings.commitKey = .shiftReturn
            settings.commitAndSendKey = .commandReturn
            let first = model.sendInstruction

            settings.commitAndSendKey = .commandShiftReturn
            let second = model.sendInstruction
            #expect(second.contains(PanelShortcut.commandShiftReturn.displayText))
            #expect(second != first)

            settings.commitAndSendKey = nil
            let third = model.sendInstruction
            #expect(third.contains(PanelShortcut.shiftReturn.displayText))
            #expect(third != second)
        }
    }

    // MARK: - スキップ

    @Test("スキップするとスキップの案内の状態になる")
    func skipShowsNotice() throws {
        try withModel { model, _, _ in
            #expect(!model.isShowingSkipNotice)

            model.skip()

            #expect(model.isShowingSkipNotice)
        }
    }

    // MARK: - 手順4の紹介(AC-19)

    @Test("AC-19: 手順4の紹介は「ホットキーの変更」と「下書き」の2つで、自動表示と確定+送信の紹介は無い")
    func nextStepIntroductions() {
        let all = TutorialNextStepIntroduction.allCases

        #expect(all == [.hotkeyChange, .draftKept])
        #expect(TutorialNextStepIntroduction.hotkeyChange.heading.contains("ホットキー"))
        #expect(TutorialNextStepIntroduction.draftKept.text.contains("esc"))
        #expect(TutorialNextStepIntroduction.draftKept.text.contains("下書き"))
        for introduction in all {
            let combined = introduction.heading + introduction.text
            #expect(!combined.contains("自動表示"))
            #expect(!combined.contains("確定+送信"))
        }
    }

    // MARK: - 開き直し(AC-20)

    @Test("AC-20: リセットすると手順1・例の吹き出しだけのチャット・空の入力欄・案内と注意なしに戻る")
    func resetReturnsToInitialState() throws {
        try withModel { model, _, _ in
            moveToNextStepsStep(model)
            model.practiceText = "something typed"
            model.skip()
            model.panelDidChange(isPresented: true, target: other, text: "")
            #expect(model.currentStep == .nextSteps)
            #expect(model.chat.messages.count > 1)

            model.reset()

            #expect(model.currentStep == .openPanel)
            #expect(model.chat == PracticeChat())
            #expect(model.chat.messages.count == 1)
            #expect(model.practiceText.isEmpty)
            #expect(!model.isShowingSkipNotice)
            #expect(!model.isShowingOtherTargetWarning)
            #expect(TutorialStep.allCases.allSatisfy { !model.isCompleted($0) })
        }
    }

    @Test("AC-20: リセットすると、覚えていた改行の数と挿入の要求を捨てる")
    func resetDiscardsRememberedState() throws {
        try withModel { model, _, _ in
            moveToSendStep(model)
            model.insertionRequested(text: "abc", target: own, sendsAfterInsert: true)

            model.reset()
            moveToSendStep(model)
            model.sendPracticeMessage("abc")

            #expect(model.currentStep == .send)
            #expect(model.chat.messages.last?.kind == .reply(.direct))
        }
    }

    @Test("途中でリセットしても、保存される設定の値は変わらない")
    func resetDoesNotChangeStoredSettings() throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.commitKey = .commandReturn
        settings.hasShownFirstLaunchTutorial = true
        let model = TutorialModel(ownProcessIdentifier: Self.ownPid, settings: settings, hotkey: { nil })

        model.panelDidChange(isPresented: true, target: own, text: "")
        model.skip()
        model.reset()

        let reloaded = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(reloaded.hasShownFirstLaunchTutorial)
        #expect(reloaded.commitKey == .commandReturn)
        #expect(settings.hasShownFirstLaunchTutorial)
    }

    @Test("練習用のチャットの入力欄へのフォーカスの要求は、要求のたびに増える")
    func practiceFocusRequestIncreases() throws {
        try withModel { model, _, _ in
            let before = model.practiceFocusRequest

            model.requestPracticeFocus()
            model.requestPracticeFocus()

            #expect(model.practiceFocusRequest == before + 2)
        }
    }

    // MARK: - 手順4

    @Test("手順4では「完了」を出し、手順1〜3では「スキップ」を出す")
    func finishButtonShowsOnlyOnNextSteps() throws {
        try withModel { model, _, _ in
            #expect(!model.showsFinishButton)
            moveToWriteStep(model)
            #expect(!model.showsFinishButton)
            model.panelDidChange(isPresented: true, target: own, text: "a\nb")
            #expect(model.currentStep == .send)
            #expect(!model.showsFinishButton)

            model.insertionRequested(text: "a\nb", target: own, sendsAfterInsert: true)
            model.sendPracticeMessage("a\nb")

            #expect(model.currentStep == .nextSteps)
            #expect(model.showsFinishButton)
        }
    }
}
