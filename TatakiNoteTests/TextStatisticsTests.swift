import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct TextStatisticsTests {
    @Test("AC-8: 文字数は空白(半角・全角・タブ)を数え、改行を数えない")
    func characterCountCountsSpacesButNotNewlines() {
        let cases: [(text: String, count: Int)] = [
            ("", 0),
            ("a b\u{3000}c\td", 7),
            ("ab\ncd", 4),
            ("ab\n", 2),
            ("\n", 0),
            ("\n\n\n", 0),
            ("a\r\nb", 2),
            ("a\rb", 2),
            ("   ", 3),
            ("日本語", 3),
            ("にほんご", 4),
        ]
        for (text, count) in cases {
            #expect(TextStatistics.characterCount(of: text) == count, "\(text.debugDescription)")
        }
    }

    @Test("AC-8: 絵文字・濁点付きの文字・結合文字・国旗は、見た目の1文字を1と数える")
    func characterCountCountsGraphemeClusters() {
        let cases: [(text: String, count: Int)] = [
            ("👨‍👩‍👧", 1),
            ("\u{304B}\u{3099}", 1),
            ("が", 1),
            ("🇯🇵", 1),
            ("👍🏽", 1),
            ("e\u{0301}", 1),
            ("a👨‍👩‍👧b\n🇯🇵", 4),
        ]
        for (text, count) in cases {
            #expect(TextStatistics.characterCount(of: text) == count, "\(text.debugDescription)")
        }
    }

    @Test("AC-9: 行数は空なら 0、それ以外は改行の数 + 1(最後が改行なら、その後ろの空の行も数える)")
    func lineCountCountsNewlines() {
        let cases: [(text: String, count: Int)] = [
            ("", 0),
            ("a", 1),
            (" ", 1),
            ("a b\u{3000}c\td", 1),
            ("ab\ncd", 2),
            ("ab\n", 2),
            ("\n", 2),
            ("\n\n", 3),
            ("a\r\nb", 2),
            ("a\r\n", 2),
            ("one\ntwo\nthree", 3),
            ("👨‍👩‍👧", 1),
        ]
        for (text, count) in cases {
            #expect(TextStatistics.lineCount(of: text) == count, "\(text.debugDescription)")
        }
    }

    @Test("AC-9: 行数は画面での折り返しを数えない(改行の無い長い文章は1行)")
    func lineCountIgnoresWrapping() {
        let longLine = String(repeating: "このリポジトリの README を読んで、", count: 200)
        #expect(TextStatistics.lineCount(of: longLine) == 1)
        #expect(TextStatistics.lineCount(of: longLine + "\n" + longLine) == 2)
    }

    @Test("AC-12: counts(of:) の文字数・行数は、空白・改行・末尾の改行・絵文字・結合文字・国旗・長い1行のすべてで characterCount・lineCount と同じ")
    func countsMatchesSeparateFunctions() {
        let cases: [String] = [
            "",
            "a b\u{3000}c\td",
            "   ",
            "ab\ncd",
            "ab\n",
            "\n",
            "\n\n\n",
            "a\r\nb",
            "a\r\n",
            "a\rb",
            "one\ntwo\nthree",
            "日本語",
            "にほんご",
            "👨‍👩‍👧",
            "\u{304B}\u{3099}",
            "🇯🇵",
            "👍🏽",
            "e\u{0301}",
            "a👨‍👩‍👧b\n🇯🇵",
            String(repeating: "このリポジトリの README を読んで、", count: 200),
            String(repeating: "このリポジトリの README を読んで、", count: 200) + "\n"
                + String(repeating: "このリポジトリの README を読んで、", count: 200),
        ]
        for text in cases {
            let counts = TextStatistics.counts(of: text)
            #expect(counts.characters == TextStatistics.characterCount(of: text), "\(text.debugDescription)")
            #expect(counts.lines == TextStatistics.lineCount(of: text), "\(text.debugDescription)")
        }
    }

    @Test("AC-12: counts(of:) は、数えた値そのものが期待どおり")
    func countsReturnsExpectedValues() {
        let cases: [(text: String, characters: Int, lines: Int)] = [
            ("", 0, 0),
            ("a b\u{3000}c\td", 7, 1),
            ("ab\ncd", 4, 2),
            ("ab\n", 2, 2),
            ("\n", 0, 2),
            ("\n\n", 0, 3),
            ("a\r\nb", 2, 2),
            ("a\rb", 2, 2),
            ("a👨‍👩‍👧b\n🇯🇵", 4, 2),
        ]
        for (text, characters, lines) in cases {
            let counts = TextStatistics.counts(of: text)
            #expect(counts.characters == characters, "\(text.debugDescription)")
            #expect(counts.lines == lines, "\(text.debugDescription)")
        }
    }

    @Test("AC-12: キーの表示文字を渡す init の帯の中身は、今の init と同じ")
    func statusBarContentFromKeyTextsMatchesShortcutInit() {
        let commandK = PanelShortcut(keyCode: 40, modifiers: [.command])
        let text = "ab\ncd\n"
        let items = PanelStatusItem.allCases
        let keyCombinations: [(PanelShortcut?, PanelShortcut?)] = [
            (.commandShiftReturn, .commandReturn),
            (commandK, nil),
            (nil, .shiftReturn),
            (nil, nil),
        ]
        for (commitKey, commitAndSendKey) in keyCombinations {
            let fromShortcuts = PanelStatusBarContent(
                text: text,
                items: items,
                commitKey: commitKey,
                commitAndSendKey: commitAndSendKey
            )
            let fromTexts = PanelStatusBarContent(
                text: text,
                items: items,
                commitKeyText: commitKey?.displayText,
                commitAndSendKeyText: commitAndSendKey?.displayText
            )
            #expect(fromTexts == fromShortcuts)
        }
    }

    @Test("AC-12: 数の項目が無い帯には、数の項目が出ない。数の項目だけ選べば、それだけが出る")
    func statusBarContentOmitsCountsWithoutCountItems() {
        let withoutCounts = PanelStatusBarContent(
            text: "ab\ncd",
            items: [.close, .lineBreak, .commit],
            commitKeyText: "⌘K",
            commitAndSendKeyText: nil
        )
        #expect(withoutCounts.entries.map(\.item) == [.close, .lineBreak, .commit])
        #expect(withoutCounts.entries.allSatisfy { entry in
            if case .count = entry { return false }
            return true
        })

        let onlyCounts = PanelStatusBarContent(
            text: "ab\ncd",
            items: [.characterCount, .lineCount],
            commitKeyText: nil,
            commitAndSendKeyText: nil
        )
        #expect(onlyCounts.entries.map(\.item) == [.characterCount, .lineCount])

        let keyTextNil = PanelStatusBarContent(
            text: "",
            items: [.commit, .commitAndSend],
            commitKeyText: nil,
            commitAndSendKeyText: "⌘↩"
        )
        #expect(keyTextNil.entries.map(\.item) == [.commitAndSend])
    }
}
