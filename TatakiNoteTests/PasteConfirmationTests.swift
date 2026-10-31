import Testing
@testable import TatakiNote

@Suite("PasteConfirmationTests")
struct PasteConfirmationTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let text: String
        let valueBefore: String
        let valueAfter: String?
        let isConfirmed: Bool

        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(name: "入った", text: "hello", valueBefore: "", valueAfter: "hello", isConfirmed: true),
        Case(name: "まだ入っていない", text: "hello", valueBefore: "", valueAfter: "", isConfirmed: false),
        Case(name: "前にコピーしたものが貼られた", text: "hello", valueBefore: "", valueAfter: "old secret", isConfirmed: false),
        Case(name: "読み直しに失敗", text: "hello", valueBefore: "", valueAfter: nil, isConfirmed: false),
        Case(name: "改行が段落に変わった", text: "line1\nline2", valueBefore: "", valueAfter: "line1\n\nline2\n", isConfirmed: true),
        Case(name: "改行が U+2028 に変わった", text: "line1\nline2", valueBefore: "", valueAfter: "line1\u{2028}line2", isConfirmed: true),
        Case(name: "同じ文がもう入っていて変わらない", text: "hello", valueBefore: "hello", valueAfter: "hello", isConfirmed: false),
        Case(name: "同じ文がもう入っていて増えた", text: "hello", valueBefore: "hello", valueAfter: "hellohello", isConfirmed: true),
        Case(name: "重なる出現は重ねて数えない", text: "aa", valueBefore: "a", valueAfter: "aaa", isConfirmed: true),
        Case(name: "分解形と合成形", text: "か\u{3099}", valueBefore: "", valueAfter: "が", isConfirmed: true),
        Case(name: "カーソルの位置に入った", text: "hello", valueBefore: "draft ", valueAfter: "draft hello", isConfirmed: true),
        Case(name: "文章が入った後に書きかけが残る", text: "hello", valueBefore: "draft", valueAfter: "hello draft", isConfirmed: true),
        Case(name: "ゼロ幅の文字が混ざる", text: "hello", valueBefore: "", valueAfter: "he\u{200B}llo\u{FFFC}", isConfirmed: true),
    ]

    @Test("AC-1: 貼り付けの前後の中身から、文章が入ったかを決める", arguments: cases)
    func confirmsByContent(_ testCase: Case) throws {
        let confirmation = try #require(PasteConfirmation(text: testCase.text, valueBefore: testCase.valueBefore))

        #expect(confirmation.isConfirmed(by: testCase.valueAfter) == testCase.isConfirmed)
    }

    @Test("AC-1: 入力欄の中身が読めなければ確かめられないものとして扱う")
    func unreadableValueBeforeIsNotConfirmable() {
        #expect(PasteConfirmation(text: "hello", valueBefore: nil) == nil)
    }

    @Test("AC-1: 文章が空白と改行だけなら確かめられないものとして扱う")
    func whitespaceOnlyTextIsNotConfirmable() {
        #expect(PasteConfirmation(text: " \n\t", valueBefore: "") == nil)
        #expect(PasteConfirmation(text: "", valueBefore: "") == nil)
        #expect(PasteConfirmation(text: "\u{200B}\u{FFFC}\u{3000}", valueBefore: "x") == nil)
    }

    @Test("AC-1: 貼り付けの前にあった同じ文章の回数を覚える")
    func remembersOccurrencesBefore() throws {
        let confirmation = try #require(PasteConfirmation(text: "hello", valueBefore: "hello hello world"))

        #expect(confirmation.normalizedText == "hello")
        #expect(confirmation.occurrencesBefore == 2)
    }

    @Test("AC-1: 比べるための形は空白・改行・U+FFFC・U+200B を取り除き NFC にそろえる")
    func normalizedRemovesIgnoredScalarsAndComposes() {
        #expect(PasteConfirmation.normalized(" a\tb\r\nc\u{2028}d\u{3000}e ") == "abcde")
        #expect(PasteConfirmation.normalized("a\u{FFFC}b\u{200B}c") == "abc")
        #expect(PasteConfirmation.normalized("か\u{3099}") == "が")
        #expect(PasteConfirmation.normalized("") == "")
        #expect(PasteConfirmation.normalized(" \n ") == "")
    }

    @Test("AC-1: 出現の回数は重ならずに数え、空の部分は 0 にする")
    func occurrencesAreNonOverlapping() {
        #expect(PasteConfirmation.occurrences(of: "aa", in: "aaa") == 1)
        #expect(PasteConfirmation.occurrences(of: "aa", in: "aaaa") == 2)
        #expect(PasteConfirmation.occurrences(of: "ab", in: "abxab") == 2)
        #expect(PasteConfirmation.occurrences(of: "abc", in: "ab") == 0)
        #expect(PasteConfirmation.occurrences(of: "", in: "abc") == 0)
        #expect(PasteConfirmation.occurrences(of: "a", in: "") == 0)
        #expect(PasteConfirmation.occurrences(of: "", in: "") == 0)
    }
}
