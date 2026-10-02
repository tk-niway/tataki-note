import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct PracticeChatTests {
    private static let returnKeyCode: UInt16 = 36
    private static let keypadEnterKeyCode: UInt16 = 76
    private static let aKeyCode: UInt16 = 0

    // MARK: - 入力欄のキーの判定(AC-9)

    @Test("AC-9: 修飾キーなしの ↩ は送信、テンキーの Enter も送信")
    func plainReturnSends() {
        #expect(PracticeChatKeyResolver.action(keyCode: Self.returnKeyCode, modifiers: [], hasMarkedText: false) == .send)
        #expect(PracticeChatKeyResolver.action(keyCode: Self.keypadEnterKeyCode, modifiers: [], hasMarkedText: false) == .send)
    }

    @Test("AC-9: 変換中の ↩ は、変換を確定してから送信する")
    func returnWithMarkedTextCommitsAndSends() {
        #expect(
            PracticeChatKeyResolver.action(keyCode: Self.returnKeyCode, modifiers: [], hasMarkedText: true)
                == .commitMarkedTextAndSend
        )
        #expect(
            PracticeChatKeyResolver.action(keyCode: Self.keypadEnterKeyCode, modifiers: [], hasMarkedText: true)
                == .commitMarkedTextAndSend
        )
    }

    @Test("AC-9: ⇧↩ は改行、変換中の ⇧↩ は送信せず入力メソッドに任せる")
    func shiftReturnInsertsNewline() {
        #expect(PracticeChatKeyResolver.action(keyCode: Self.returnKeyCode, modifiers: [.shift], hasMarkedText: false) == .insertNewline)
        #expect(PracticeChatKeyResolver.action(keyCode: Self.keypadEnterKeyCode, modifiers: [.shift], hasMarkedText: false) == .insertNewline)
        #expect(PracticeChatKeyResolver.action(keyCode: Self.returnKeyCode, modifiers: [.shift], hasMarkedText: true) == .passThrough)
    }

    @Test("AC-9: ⌘↩・⌥↩・⌃↩・⇧⌘↩ は送信も改行もしない")
    func otherModifiersPassThrough() {
        let combinations: [NSEvent.ModifierFlags] = [
            [.command], [.option], [.control], [.command, .shift], [.option, .shift],
        ]
        for modifiers in combinations {
            for hasMarkedText in [false, true] {
                #expect(
                    PracticeChatKeyResolver.action(keyCode: Self.returnKeyCode, modifiers: modifiers, hasMarkedText: hasMarkedText)
                        == .passThrough
                )
            }
        }
    }

    @Test("AC-9: Caps Lock と fn は修飾キーとして数えない")
    func capsLockAndFunctionAreIgnored() {
        #expect(
            PracticeChatKeyResolver.action(keyCode: Self.returnKeyCode, modifiers: [.capsLock], hasMarkedText: false) == .send
        )
        #expect(
            PracticeChatKeyResolver.action(keyCode: Self.returnKeyCode, modifiers: [.function], hasMarkedText: false) == .send
        )
        #expect(
            PracticeChatKeyResolver.action(keyCode: Self.returnKeyCode, modifiers: [.shift, .capsLock], hasMarkedText: false)
                == .insertNewline
        )
    }

    @Test("AC-9: ↩ と Enter 以外のキーは、修飾キーや変換中でもふつうの入力に任せる")
    func nonReturnKeysPassThrough() {
        for modifiers: NSEvent.ModifierFlags in [[], [.shift], [.command]] {
            for hasMarkedText in [false, true] {
                #expect(
                    PracticeChatKeyResolver.action(keyCode: Self.aKeyCode, modifiers: modifiers, hasMarkedText: hasMarkedText)
                        == .passThrough
                )
            }
        }
    }

    // MARK: - 入力欄のプレースホルダー

    @Test("入力欄のプレースホルダーは空でない")
    func inputPlaceholderIsNotEmpty() {
        #expect(!PracticeChat.inputPlaceholder.isEmpty)
    }

    // MARK: - 吹き出しの並び(AC-6, AC-7)

    @Test("AC-6: 作った直後の練習用のチャットには、例の吹き出しだけがある")
    func initialChatHasOnlyExample() {
        let chat = PracticeChat()

        #expect(chat.messages.count == 1)
        #expect(chat.messages[0].id == 0)
        #expect(chat.messages[0].kind == .example)
        #expect(chat.messages[0].text == PracticeChat.exampleText)
        #expect(!PracticeChat.exampleText.isEmpty)
        #expect(!PracticeChat.exampleCaption.isEmpty)
    }

    @Test("AC-7: 送った文章がそのまま自分の吹き出しとして末尾に並び、続けて返事の吹き出しが並ぶ")
    func appendSentAddsSentAndReplyAtEnd() {
        var chat = PracticeChat()

        chat.appendSent("  hello\nworld ", reply: "返事です", route: .direct)

        #expect(chat.messages.count == 3)
        #expect(chat.messages[0].kind == .example)
        #expect(chat.messages[1].kind == .sent)
        #expect(chat.messages[1].text == "  hello\nworld ")
        #expect(chat.messages[2].kind == .reply(.direct))
        #expect(chat.messages[2].text == "返事です")
    }

    @Test("AC-7: 続けて送ると、吹き出しは足した順に並び、id は連番で重ならない")
    func appendSentKeepsOrderAndUniqueIDs() {
        var chat = PracticeChat()

        chat.appendSent("one", reply: "r1", route: .commitAndSend)
        chat.appendSent("two", reply: "r2", route: .commitThenReturn)

        #expect(chat.messages.map(\.text) == [PracticeChat.exampleText, "one", "r1", "two", "r2"])
        #expect(chat.messages.map(\.id) == [0, 1, 2, 3, 4])
        #expect(chat.messages[4].kind == .reply(.commitThenReturn))
    }

    @Test("AC-7: 返事の吹き出しには、AI の返事ではないと分かる印の文がある")
    func replyLabelIsNotEmptyAndNotAI() {
        #expect(!PracticeChat.replyLabel.isEmpty)
        #expect(PracticeChat.replyLabel.contains("自動"))
    }

    // MARK: - 返事の文(AC-11, AC-12, AC-13)

    @Test("AC-11: 直接書いて送ったときの返事は、パネルで書くよう促し、今のホットキーの表記が入る")
    func directReplyMentionsHotkey() {
        let text = PracticeChatReply.text(for: .direct, commitAndSendKey: "⌘↩", hotkey: "⌥⇧Space")

        #expect(text.contains("⌥⇧Space"))
        #expect(text.contains("パネル"))
    }

    @Test("AC-11: ホットキーが無いときの返事は、メニューバーの「パネルを開く」を案内する")
    func directReplyWithoutHotkeyMentionsMenuBar() {
        let text = PracticeChatReply.text(for: .direct, commitAndSendKey: "⌘↩", hotkey: nil)

        #expect(text.contains("メニューバー"))
        #expect(text.contains("パネルを開く"))
    }

    @Test("AC-12: 確定+送信キーで送ったときの返事は、今のキーの表記と、Enter を変換の確定や改行に使えることを含む")
    func commitAndSendReplyMentionsKeyAndEnter() {
        let text = PracticeChatReply.text(for: .commitAndSend, commitAndSendKey: "⌘↩", hotkey: "⌥⇧Space")

        #expect(text.contains("⌘↩"))
        #expect(text.contains("送信"))
        #expect(text.contains("改行"))
        #expect(text.contains("変換の確定"))
    }

    @Test("AC-12: 確定+送信キーを後で消していれば、キーの表記の代わりに「確定+送信キー」と書く")
    func commitAndSendReplyWithoutKeyUsesName() {
        let text = PracticeChatReply.text(for: .commitAndSend, commitAndSendKey: nil, hotkey: "⌥⇧Space")

        #expect(text.contains("確定+送信キー"))
        #expect(text.contains("送信"))
        #expect(text.contains("改行"))
    }

    @Test("AC-13: 確定キーで入れて自分で送ったときの返事は、送信できたことと、確定+送信キーなら一度にできることを含む")
    func commitThenReturnReplyMentionsOneStep() {
        let text = PracticeChatReply.text(for: .commitThenReturn, commitAndSendKey: "⌘↩", hotkey: "⌥⇧Space")

        #expect(text.contains("送信できました"))
        #expect(text.contains("⌘↩"))
        #expect(text.contains("一度に"))
        #expect(text.contains("改行"))
    }

    @Test("AC-13: 確定+送信キーが無いときの返事は、設定の「一般」で登録できると書く")
    func commitThenReturnReplyWithoutKeyPointsToSettings() {
        let text = PracticeChatReply.text(for: .commitThenReturn, commitAndSendKey: nil, hotkey: "⌥⇧Space")

        #expect(text.contains("送信できました"))
        #expect(text.contains("設定の「一般」"))
        #expect(text.contains("登録"))
        #expect(text.contains("一度に"))
        #expect(text.contains("改行"))
    }
}
