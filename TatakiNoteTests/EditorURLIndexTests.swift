import Foundation
import Testing
@testable import TatakiNote

struct EditorURLIndexTests {
    private let sample = "前置き https://example.com/a(b)c 中\nhttp://x.jp/path?q=1#f, と😀 https://example.com/docs/2026/11/some-page.\n\nabchttps://no.example 後"

    private let threeParagraphs = "a b\nhttps://example.com/x\nlast"

    private func insertion(_ location: Int, inserted: String) -> EditorTextEdit {
        EditorTextEdit(
            range: NSRange(location: location, length: inserted.utf16.count),
            changeInLength: inserted.utf16.count
        )
    }

    private func deletion(_ location: Int, length: Int) -> EditorTextEdit {
        EditorTextEdit(range: NSRange(location: location, length: 0), changeInLength: -length)
    }

    private func apply(_ edit: EditorTextEdit, inserting string: String, to text: NSMutableString) {
        text.replaceCharacters(in: edit.originalRange, with: string)
    }

    private func indexed(_ text: String) -> (index: EditorURLIndex, text: NSMutableString) {
        var index = EditorURLIndex()
        let mutable = NSMutableString(string: text)
        _ = index.update(in: mutable)
        return (index, mutable)
    }

    private func isParagraphAligned(_ range: NSRange, in text: NSString) -> Bool {
        let startAligned = range.location == 0 || text.character(at: range.location - 1) == 0x0A
        let endAligned = NSMaxRange(range) == text.length
            || (NSMaxRange(range) > 0 && text.character(at: NSMaxRange(range) - 1) == 0x0A)
        return startAligned && endAligned
    }

    // MARK: - EditorTextEdit

    @Test("AC-1: 位置 5 に1文字入れたとき、前はそのまま・後ろはずらし・重なる、接するは nil になる")
    func shiftedAfterInsertion() {
        let edit = EditorTextEdit(range: NSRange(location: 5, length: 1), changeInLength: 1)
        #expect(edit.originalRange == NSRange(location: 5, length: 0))
        #expect(edit.shifted(NSRange(location: 0, length: 4)) == NSRange(location: 0, length: 4))
        #expect(edit.shifted(NSRange(location: 0, length: 5)) == nil)
        #expect(edit.shifted(NSRange(location: 5, length: 3)) == nil)
        #expect(edit.shifted(NSRange(location: 6, length: 3)) == NSRange(location: 7, length: 3))
        #expect(edit.shifted(NSRange(location: 3, length: 4)) == nil)
    }

    @Test("AC-1: 位置 5 から2文字消したとき、前はそのまま・後ろは詰め、重なる・接するは nil になる")
    func shiftedAfterDeletion() {
        let edit = EditorTextEdit(range: NSRange(location: 5, length: 0), changeInLength: -2)
        #expect(edit.originalRange == NSRange(location: 5, length: 2))
        #expect(edit.shifted(NSRange(location: 0, length: 5)) == nil)
        #expect(edit.shifted(NSRange(location: 0, length: 4)) == NSRange(location: 0, length: 4))
        #expect(edit.shifted(NSRange(location: 8, length: 2)) == NSRange(location: 6, length: 2))
        #expect(edit.shifted(NSRange(location: 7, length: 2)) == nil)
    }

    @Test("AC-1: 置き換えの変更の前の範囲は、置き換わった長さから求める")
    func originalRangeOfReplacement() {
        let edit = EditorTextEdit(range: NSRange(location: 2, length: 3), changeInLength: 1)
        #expect(edit.originalRange == NSRange(location: 2, length: 2))
    }

    // MARK: - 全文との一致

    @Test("AC-1: 最初の update は全文を探す")
    func firstUpdateDetectsWhole() {
        var index = EditorURLIndex()
        let text = sample as NSString
        let change = index.update(in: text)
        #expect(change.isWhole)
        #expect(change.redetectedRange == NSRange(location: 0, length: text.length))
        #expect(index.urls == EditorURLDetector.urls(in: text))
        #expect(!index.urls.isEmpty)
    }

    @Test("AC-1: すべての位置に打つ・すべての1文字を消した後の一覧が、全文から探した結果と同じになる")
    func singleEditsMatchWholeDetection() {
        let insertions = ["x", " ", "\n", "a", "https://"]
        let length = (sample as NSString).length
        for location in 0...length {
            for inserted in insertions {
                var (index, text) = indexed(sample)
                let edit = insertion(location, inserted: inserted)
                apply(edit, inserting: inserted, to: text)
                index.record(edit)
                let change = index.update(in: text)
                #expect(index.urls == EditorURLDetector.urls(in: text), "位置 \(location) に \(inserted.debugDescription) を入れた")
                if let range = change.redetectedRange, !change.isWhole {
                    #expect(isParagraphAligned(range, in: text), "位置 \(location) の探し直した範囲 \(range)")
                }
            }
        }
        for location in 0..<length {
            var (index, text) = indexed(sample)
            let edit = deletion(location, length: 1)
            apply(edit, inserting: "", to: text)
            index.record(edit)
            let change = index.update(in: text)
            #expect(index.urls == EditorURLDetector.urls(in: text), "位置 \(location) の1文字を消した")
            if let range = change.redetectedRange, !change.isWhole {
                #expect(isParagraphAligned(range, in: text), "位置 \(location) を消した探し直した範囲 \(range)")
            }
        }
    }

    @Test("AC-1: 続けて記録した2つの変更をまとめて反映した一覧が、全文から探した結果と同じになる")
    func pairedEditsMatchWholeDetection() {
        let length = (sample as NSString).length
        let firstInsertions = ["x", "\n", "https://a.b"]
        let secondInsertions = ["y", " ", "\n"]
        for firstLocation in stride(from: 0, through: length, by: 3) {
            for first in firstInsertions {
                var (index, text) = indexed(sample)
                let firstEdit = insertion(firstLocation, inserted: first)
                apply(firstEdit, inserting: first, to: text)
                index.record(firstEdit)
                for secondLocation in stride(from: 0, through: text.length, by: 4) {
                    for second in secondInsertions {
                        var pair = index
                        let copy = NSMutableString(string: text as String)
                        let secondEdit = insertion(secondLocation, inserted: second)
                        apply(secondEdit, inserting: second, to: copy)
                        pair.record(secondEdit)
                        _ = pair.update(in: copy)
                        #expect(
                            pair.urls == EditorURLDetector.urls(in: copy),
                            "\(firstLocation) に \(first.debugDescription)、\(secondLocation) に \(second.debugDescription)"
                        )
                    }
                    var pair = index
                    let copy = NSMutableString(string: text as String)
                    if secondLocation < copy.length {
                        let secondEdit = deletion(secondLocation, length: 1)
                        apply(secondEdit, inserting: "", to: copy)
                        pair.record(secondEdit)
                        _ = pair.update(in: copy)
                        #expect(
                            pair.urls == EditorURLDetector.urls(in: copy),
                            "\(firstLocation) に \(first.debugDescription)、\(secondLocation) の1文字を消した"
                        )
                    }
                }
            }
        }
    }

    @Test("AC-1: 先頭と末尾・前と後ろ・重なる2つの変更をまとめて反映できる")
    func combinedEditsAtEdges() {
        let combos: [(first: (Int, String), second: (Int, String))] = [
            ((0, "a"), (1, "b")),
            ((5, "x"), (3, "y")),
            ((10, "\n"), (10, "z")),
            ((10, "zz"), (11, "\n")),
            ((0, "https://x"), (0, "q")),
        ]
        for combo in combos {
            var (index, text) = indexed(sample)
            let first = insertion(combo.first.0, inserted: combo.first.1)
            apply(first, inserting: combo.first.1, to: text)
            index.record(first)
            let second = insertion(combo.second.0, inserted: combo.second.1)
            apply(second, inserting: combo.second.1, to: text)
            index.record(second)
            _ = index.update(in: text)
            #expect(index.urls == EditorURLDetector.urls(in: text), "\(combo)")
        }
    }

    @Test("AC-1: URL を貼ったときと、複数文字の置き換えの後の一覧が、全文から探した結果と同じになる")
    func pasteAndReplace() {
        let pasted = "https://example.com/pasted?x=1"
        var (index, text) = indexed(sample)
        let paste = insertion(8, inserted: pasted)
        apply(paste, inserting: pasted, to: text)
        index.record(paste)
        _ = index.update(in: text)
        #expect(index.urls == EditorURLDetector.urls(in: text))

        let replaceRange = NSRange(location: 2, length: 20)
        let replacement = "置き換え"
        let replace = EditorTextEdit(
            range: NSRange(location: replaceRange.location, length: replacement.utf16.count),
            changeInLength: replacement.utf16.count - replaceRange.length
        )
        text.replaceCharacters(in: replaceRange, with: replacement)
        index.record(replace)
        _ = index.update(in: text)
        #expect(index.urls == EditorURLDetector.urls(in: text))
    }

    @Test("AC-1: 文章をまるごと入れ替えた後の一覧が、全文から探した結果と同じになる")
    func replacingWholeText() {
        var (index, text) = indexed(sample)
        let replacement = "新しい https://new.example/path と http://b.jp"
        let whole = EditorTextEdit(
            range: NSRange(location: 0, length: replacement.utf16.count),
            changeInLength: replacement.utf16.count - text.length
        )
        text.setString(replacement)
        index.record(whole)
        _ = index.update(in: text)
        #expect(index.urls == EditorURLDetector.urls(in: text))
    }

    @Test("AC-1: 通知を取りこぼして長さが合わないときは全文を探し直す")
    func missedNotificationRedetectsWhole() {
        var (index, text) = indexed(sample)
        text.insert("https://missed.example ", at: 0)
        let withoutRecord = index.update(in: text)
        #expect(withoutRecord.isWhole)
        #expect(index.urls == EditorURLDetector.urls(in: text))

        let wrong = insertion(0, inserted: "x")
        text.insert("xyz", at: 0)
        index.record(wrong)
        let withWrongRecord = index.update(in: text)
        #expect(withWrongRecord.isWhole)
        #expect(withWrongRecord.edits == [wrong])
        #expect(index.urls == EditorURLDetector.urls(in: text))
    }

    @Test("AC-1: invalidate の後の update は全文を探し直し、記録を捨てる")
    func invalidateRedetectsWhole() {
        var (index, text) = indexed(sample)
        let inserted = insertion(0, inserted: "x")
        apply(inserted, inserting: "x", to: text)
        index.record(inserted)
        #expect(index.hasPendingEdits)
        index.invalidate()
        #expect(!index.hasPendingEdits)
        let change = index.update(in: text)
        #expect(change.isWhole)
        #expect(change.edits.isEmpty)
        #expect(index.urls == EditorURLDetector.urls(in: text))
    }

    @Test("AC-1: 空の文章に打った後の一覧が、全文から探した結果と同じになる")
    func typingIntoEmptyText() {
        var (index, text) = indexed("")
        #expect(index.urls.isEmpty)
        let typed = insertion(0, inserted: "https://a.com")
        apply(typed, inserting: "https://a.com", to: text)
        index.record(typed)
        let change = index.update(in: text)
        #expect(change.redetectedRange == NSRange(location: 0, length: text.length))
        #expect(index.urls == EditorURLDetector.urls(in: text))
        #expect(index.urls.count == 1)
    }

    // MARK: - 境界の表

    @Test("AC-1: 段落の途中に1文字打つと、その段落だけ探し直し、URL は1文字ぶん後ろへ移る")
    func typingInFirstParagraph() {
        var (index, text) = indexed(threeParagraphs)
        let before = index.urls
        let typed = insertion(1, inserted: "z")
        apply(typed, inserting: "z", to: text)
        index.record(typed)
        let change = index.update(in: text)
        #expect(change.redetectedRange == NSRange(location: 0, length: 5))
        #expect(change.edits == [typed])
        #expect(!change.isWhole)
        #expect(index.urls.map(\.text) == before.map(\.text))
        #expect(index.urls.map(\.range.location) == before.map { $0.range.location + 1 })
    }

    @Test("AC-1: URL の直後に打つと、URL は打った文字を含んで伸びる")
    func typingAfterURL() {
        var (index, text) = indexed(threeParagraphs)
        let urlEnd = NSMaxRange(index.urls[0].range)
        let typed = insertion(urlEnd, inserted: "x")
        apply(typed, inserting: "x", to: text)
        index.record(typed)
        let change = index.update(in: text)
        #expect(change.redetectedRange == NSRange(location: 4, length: 23))
        #expect(index.urls.map(\.text) == ["https://example.com/xx"])
        #expect(index.urls == EditorURLDetector.urls(in: text))
    }

    @Test("AC-1: URL の直前に英字を打つと、URL でなくなる")
    func typingLetterBeforeURL() {
        var (index, text) = indexed(threeParagraphs)
        let typed = insertion(4, inserted: "a")
        apply(typed, inserting: "a", to: text)
        index.record(typed)
        let change = index.update(in: text)
        #expect(index.urls.isEmpty)
        let range = change.redetectedRange ?? NSRange(location: 0, length: 0)
        #expect(NSLocationInRange(5, range))
        #expect(isParagraphAligned(range, in: text))
    }

    @Test("AC-1: 段落の終わりの改行を消すと、つながった段落を探し直し、直前が英数字なら URL でなくなる")
    func deletingNewlineBeforeURLParagraph() {
        var (index, text) = indexed(threeParagraphs)
        let removal = deletion(3, length: 1)
        apply(removal, inserting: "", to: text)
        index.record(removal)
        let change = index.update(in: text)
        #expect(text as String == "a bhttps://example.com/x\nlast")
        #expect(index.urls == EditorURLDetector.urls(in: text))
        #expect(index.urls.isEmpty)
        #expect(change.redetectedRange == NSRange(location: 0, length: 25))
    }

    @Test("AC-1: 英数字でない文字の後ろに改行を消してつなぐと、URL の位置が1つ前へ移る")
    func deletingNewlineKeepsURL() {
        var (index, text) = indexed("a \nhttps://example.com/x\nlast")
        let removal = deletion(2, length: 1)
        apply(removal, inserting: "", to: text)
        index.record(removal)
        _ = index.update(in: text)
        #expect(index.urls == EditorURLDetector.urls(in: text))
        #expect(index.urls.map(\.range.location) == [2])
    }

    @Test("AC-1: URL の中に改行を打つと、改行の前の段落で URL が切れる")
    func newlineInsideURL() {
        var (index, text) = indexed(threeParagraphs)
        let location = index.urls[0].range.location + 12
        let typed = insertion(location, inserted: "\n")
        apply(typed, inserting: "\n", to: text)
        index.record(typed)
        let change = index.update(in: text)
        #expect(index.urls == EditorURLDetector.urls(in: text))
        #expect(index.urls.map(\.text) == ["https://exam"])
        let range = change.redetectedRange ?? NSRange(location: 0, length: 0)
        #expect(NSLocationInRange(location, range))
        #expect(isParagraphAligned(range, in: text))
    }

    // MARK: - 探し直す範囲

    private func longText() -> (text: String, urlParagraphs: Set<Int>) {
        var urlParagraphs: Set<Int> = []
        let paragraphs = (0..<200).map { number -> String in
            var line = "段落 \(number) の本文です。ここに文章が入ります"
            if number % 5 == 0 {
                urlParagraphs.insert(number)
                line += " https://example.com/docs/2026/11/page-\(number)/section?query=\(number)#top"
            }
            return line
        }
        return (paragraphs.joined(separator: "\n"), urlParagraphs)
    }

    @Test("AC-3: URL の無い段落で1文字打つと、探し直すのはその段落だけになる")
    func typingInURLFreeParagraphRedetectsOnlyThatParagraph() {
        let (source, urlParagraphs) = longText()
        #expect(urlParagraphs.count == 40)
        var (index, text) = indexed(source)
        #expect(index.urls.count == 40)

        let paragraphStart = text.range(of: "段落 101 の").location
        #expect(paragraphStart != NSNotFound)
        let location = paragraphStart + 4
        let typed = insertion(location, inserted: "x")
        apply(typed, inserting: "x", to: text)
        index.record(typed)
        let change = index.update(in: text)

        let expected = text.paragraphRange(for: NSRange(location: location, length: 1))
        #expect(change.redetectedRange == expected)
        #expect(!change.isWhole)
        #expect(expected.length < 60)
        #expect(index.urls == EditorURLDetector.urls(in: text))
    }

    @Test("AC-3: 文章が変わらず選択だけが動いたときは探し直さない")
    func selectionOnlyDoesNotRedetect() {
        let (source, _) = longText()
        var (index, text) = indexed(source)
        let before = index.urls

        let typed = insertion(10, inserted: "x")
        apply(typed, inserting: "x", to: text)
        index.record(typed)
        _ = index.update(in: text)

        let change = index.update(in: text)
        #expect(change.redetectedRange == nil)
        #expect(change.edits.isEmpty)
        #expect(!change.isWhole)
        #expect(index.urls.count == before.count)
        #expect(index.urls == EditorURLDetector.urls(in: text))
    }

    @Test("AC-3: 探し直す範囲は文章の長さによらず、変えた段落の大きさで決まる")
    func redetectedRangeDoesNotGrowWithText() {
        let paragraph = "段落の本文です"
        for count in [10, 100, 1000] {
            let source = Array(repeating: paragraph, count: count).joined(separator: "\n")
            var (index, text) = indexed(source)
            let typed = insertion(paragraph.utf16.count * 3 + 3 + 2, inserted: "x")
            apply(typed, inserting: "x", to: text)
            index.record(typed)
            let change = index.update(in: text)
            #expect(change.redetectedRange?.length == paragraph.utf16.count + 2)
        }
    }
}
