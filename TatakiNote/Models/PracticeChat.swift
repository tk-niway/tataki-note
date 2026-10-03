import AppKit
import Foundation

/// 練習用のチャットの入力欄で、キーを押したときの動き。
enum PracticeChatKeyAction: Equatable {
    case send
    case commitMarkedTextAndSend
    case insertNewline
    case passThrough
}

/// 練習用のチャットの入力欄のキーの判定。
enum PracticeChatKeyResolver {
    private static let returnKeyCode: UInt16 = 36
    private static let keypadEnterKeyCode: UInt16 = 76

    /// 押されたキーと修飾キー、変換中かどうかから、入力欄の動きを決める。
    static func action(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, hasMarkedText: Bool) -> PracticeChatKeyAction {
        guard keyCode == returnKeyCode || keyCode == keypadEnterKeyCode else { return .passThrough }
        let relevant = modifiers.intersection(PanelShortcut.relevantModifiers)
        if relevant.isEmpty {
            return hasMarkedText ? .commitMarkedTextAndSend : .send
        }
        if relevant == [.shift] {
            return hasMarkedText ? .passThrough : .insertNewline
        }
        return .passThrough
    }
}

/// 練習用のチャットで、送った文章がどこから来たか。
enum PracticeChatSendRoute: Equatable {
    case commitAndSend
    case commitThenReturn
    case direct
}

/// 練習用のチャットの吹き出し。
struct PracticeChatMessage: Identifiable, Equatable {
    enum Kind: Equatable {
        case example
        case sent
        case reply(PracticeChatSendRoute)
    }

    let id: Int
    let kind: Kind
    let text: String
}

/// 練習用のチャットの吹き出しの並び。
struct PracticeChat: Equatable {
    /// 例の吹き出しの文(書きかけで切れた文)。
    static var exampleText: String {
        String(localized: "明日の打ち合わせの件ですが、資料の")
    }

    /// 例の吹き出しに添える説明。
    static var exampleCaption: String {
        String(localized: "変換の確定や改行のつもりで Enter を押して、書きかけのまま送られてしまった例です。")
    }

    /// 返事の吹き出しに添える、AI の返事ではないことの印。
    static var replyLabel: String {
        String(localized: "練習用の自動の返事")
    }

    /// 入力欄が空のあいだに出す文。
    static var inputPlaceholder: String {
        String(localized: "メッセージを入力")
    }

    private(set) var messages: [PracticeChatMessage]

    init() {
        messages = [PracticeChatMessage(id: 0, kind: .example, text: Self.exampleText)]
    }

    /// 送った文章と返事を末尾に足す。
    mutating func appendSent(_ text: String, reply: String, route: PracticeChatSendRoute) {
        let sentID = messages.count
        messages.append(PracticeChatMessage(id: sentID, kind: .sent, text: text))
        messages.append(PracticeChatMessage(id: sentID + 1, kind: .reply(route), text: reply))
    }
}

/// 練習用のチャットの定型の返事。
enum PracticeChatReply {
    /// 送った経路と今のキーの表記から、定型の返事の文を作る。
    static func text(
        for route: PracticeChatSendRoute,
        commitAndSendKey: String?,
        hotkey: String?
    ) -> String {
        switch route {
        case .commitAndSend:
            let key = commitAndSendKey ?? String(localized: "確定+送信キー")
            return String(localized: "\(key) で送信できました。パネルの中では、Enter を変換の確定や改行に使えます。送られるのは \(key) を押したときだけです。")
        case .commitThenReturn:
            let batch: String
            if let commitAndSendKey {
                batch = String(localized: "\(commitAndSendKey) を使うと、入れるのと送るのを一度にできます。")
            } else {
                batch = String(localized: "設定の「一般」で確定+送信キーを登録すると、入れるのと送るのを一度にできます。")
            }
            return String(localized: "送信できました。") + batch
                + String(localized: "パネルの中では、Enter を変換の確定や改行に使えます。")
        case .direct:
            let opening: String
            if let hotkey {
                opening = String(localized: "\(hotkey) でパネルを開いて書いてみましょう。")
            } else {
                opening = String(localized: "メニューバーの「パネルを開く」でパネルを開いて書いてみましょう。")
            }
            return String(localized: "この欄に直接書くと、変換の確定や改行のつもりの Enter で送られてしまいます。") + opening
        }
    }
}
