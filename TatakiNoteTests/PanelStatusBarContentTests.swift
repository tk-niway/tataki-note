import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct PanelStatusBarContentTests {
    private typealias Entry = PanelStatusBarContent.Entry

    private func makeContent(text: String, settings: AppSettings) -> PanelStatusBarContent {
        PanelStatusBarContent(
            text: text,
            items: settings.panelStatusItems,
            commitKey: settings.commitKey,
            commitAndSendKey: settings.commitAndSendKey
        )
    }

    @Test("AC-4: 何も設定していなければ esc 閉じる・改行・⇧⌘↩ 確定・⌘↩ 確定+送信・0文字・0行が出て、閉じるに「(下書きは残ります)」は付かない")
    func defaultContent() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))

        let content = makeContent(text: "", settings: settings)
        #expect(content.entries == [
            .keyHint(item: .close, key: "esc", label: "閉じる"),
            .keyHint(item: .lineBreak, key: "↩", label: "改行"),
            .keyHint(item: .commit, key: "⇧⌘↩", label: "確定"),
            .keyHint(item: .commitAndSend, key: "⌘↩", label: "確定+送信"),
            .count(item: .characterCount, text: "0文字"),
            .count(item: .lineCount, text: "0行"),
        ])
        #expect(content.isEmpty == false)
        #expect(content.entries.map(\.id) == [.close, .lineBreak, .commit, .commitAndSend, .characterCount, .lineCount])
    }

    @Test("AC-20: 確定・確定+送信の項目は、登録したキーの表記(Return 以外の任意のキーを含む)で出る")
    func keyHintsFollowKeys() {
        let commandK = PanelShortcut(keyCode: 40, modifiers: [.command])
        let cases: [(PanelShortcut?, PanelShortcut?, [Entry])] = [
            (.shiftReturn, .commandShiftReturn, [
                .keyHint(item: .commit, key: "⇧↩", label: "確定"),
                .keyHint(item: .commitAndSend, key: "⇧⌘↩", label: "確定+送信"),
            ]),
            (.commandReturn, .shiftReturn, [
                .keyHint(item: .commit, key: "⌘↩", label: "確定"),
                .keyHint(item: .commitAndSend, key: "⇧↩", label: "確定+送信"),
            ]),
            (.commandShiftReturn, .commandReturn, [
                .keyHint(item: .commit, key: "⇧⌘↩", label: "確定"),
                .keyHint(item: .commitAndSend, key: "⌘↩", label: "確定+送信"),
            ]),
            (commandK, .commandReturn, [
                .keyHint(item: .commit, key: "⌘K", label: "確定"),
                .keyHint(item: .commitAndSend, key: "⌘↩", label: "確定+送信"),
            ]),
        ]
        for (commitKey, commitAndSendKey, expected) in cases {
            let content = PanelStatusBarContent(
                text: "",
                items: [.commit, .commitAndSend],
                commitKey: commitKey,
                commitAndSendKey: commitAndSendKey
            )
            #expect(content.entries == expected, "\(String(describing: commitKey)) / \(String(describing: commitAndSendKey))")
        }
    }

    @Test("AC-17: キーが登録なし(nil)なら、項目の一覧に入っていても(表示の設定に関わらず)出さない")
    func unassignedKeysAreNotShown() {
        let withoutCommit = PanelStatusBarContent(
            text: "",
            items: PanelStatusItem.allCases,
            commitKey: nil,
            commitAndSendKey: .commandShiftReturn
        )
        #expect(withoutCommit.entries.map(\.item) == [.close, .lineBreak, .commitAndSend, .characterCount, .lineCount])
        #expect(withoutCommit.entries.contains(.keyHint(item: .commitAndSend, key: "⇧⌘↩", label: "確定+送信")))

        let withoutBoth = PanelStatusBarContent(
            text: "",
            items: PanelStatusItem.allCases,
            commitKey: nil,
            commitAndSendKey: nil
        )
        #expect(withoutBoth.entries.map(\.item) == [.close, .lineBreak, .characterCount, .lineCount])

        let onlyUnassignedKeys = PanelStatusBarContent(
            text: "abc",
            items: [.commit, .commitAndSend],
            commitKey: nil,
            commitAndSendKey: nil
        )
        #expect(onlyUnassignedKeys.isEmpty)
    }

    @Test("AC-20: 設定のキーを変えると、帯の確定・確定+送信の印が変わり、登録を消すと消える")
    func keyHintsFollowSettings() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))

        settings.commitKey = .shiftReturn
        settings.commitAndSendKey = .commandShiftReturn
        var entries = makeContent(text: "", settings: settings).entries
        #expect(entries.contains(.keyHint(item: .commit, key: "⇧↩", label: "確定")))
        #expect(entries.contains(.keyHint(item: .commitAndSend, key: "⇧⌘↩", label: "確定+送信")))

        settings.commitKey = nil
        entries = makeContent(text: "", settings: settings).entries
        #expect(!entries.map(\.item).contains(.commit))
        #expect(entries.contains(.keyHint(item: .commitAndSend, key: "⇧⌘↩", label: "確定+送信")))
    }

    @Test("AC-8, AC-9: 数の項目は今の文章の文字数・行数(空白は数え、改行は数えない)")
    func countsFollowText() {
        let cases: [(text: String, characters: String, lines: String)] = [
            ("", "0文字", "0行"),
            ("ab\nc d", "5文字", "2行"),
            ("ab\nc d\n", "5文字", "3行"),
            ("a b\u{3000}c\td", "7文字", "1行"),
            ("\n", "0文字", "2行"),
            ("👨‍👩‍👧\u{304B}\u{3099}🇯🇵", "3文字", "1行"),
            ("にほんご", "4文字", "1行"),
        ]
        for (text, characters, lines) in cases {
            let content = PanelStatusBarContent(
                text: text,
                items: [.characterCount, .lineCount],
                commitKey: .commandReturn,
                commitAndSendKey: nil
            )
            #expect(content.entries == [
                .count(item: .characterCount, text: characters),
                .count(item: .lineCount, text: lines),
            ], "\(text.debugDescription)")
        }
    }

    @Test("AC-8, AC-9: 1,000 以上の数は3桁ごとに区切る(区切りの記号は地域の設定に従う)")
    func largeCountsAreGrouped() {
        let text = String(repeating: "a", count: 1284) + String(repeating: "\n", count: 1099)
        let content = PanelStatusBarContent(
            text: text,
            items: [.characterCount, .lineCount],
            commitKey: .commandReturn,
            commitAndSendKey: nil
        )
        #expect(content.entries == [
            .count(item: .characterCount, text: "\(1284.formatted())文字"),
            .count(item: .lineCount, text: "\(1100.formatted())行"),
        ])
    }

    @Test("AC-10: 非表示にした項目は出さず、残りを並びの順に詰める。すべて非表示なら空")
    func hiddenItemsAreNotShown() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.commitKey = .commandReturn
        settings.commitAndSendKey = .commandShiftReturn

        settings.hiddenPanelStatusItems = [.characterCount]
        #expect(makeContent(text: "ab", settings: settings).entries.map(\.item) == [
            .close, .lineBreak, .commit, .commitAndSend, .lineCount,
        ])

        settings.hiddenPanelStatusItems = [.lineBreak, .close]
        #expect(makeContent(text: "ab", settings: settings).entries == [
            .keyHint(item: .commit, key: "⌘↩", label: "確定"),
            .keyHint(item: .commitAndSend, key: "⇧⌘↩", label: "確定+送信"),
            .count(item: .characterCount, text: "2文字"),
            .count(item: .lineCount, text: "1行"),
        ])

        settings.hiddenPanelStatusItems = [.lineBreak, .close, .commit, .commitAndSend]
        #expect(makeContent(text: "ab", settings: settings).entries.map(\.item) == [.characterCount, .lineCount])

        settings.hiddenPanelStatusItems = Set(PanelStatusItem.allCases)
        let empty = makeContent(text: "ab", settings: settings)
        #expect(empty.isEmpty)
        #expect(empty.entries.isEmpty)
    }
}
