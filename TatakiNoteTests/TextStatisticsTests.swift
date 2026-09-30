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
            // @note p0-1110
            ("👨‍👩‍👧", 1),
            // @note p0-1111
            ("\u{304B}\u{3099}", 1),
            // @note p0-1112
            ("が", 1),
            // @note p0-1113
            ("🇯🇵", 1),
            // @note p0-1114
            ("👍🏽", 1),
            // @note p0-1115
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
}
