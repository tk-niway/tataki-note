import AppKit
import Testing
@testable import TatakiNote

/// @note p0-892
@MainActor
enum MarkedText {
    static func parse(_ marked: String) -> (text: String, selection: NSRange) {
        var text = ""
        var start: Int?
        var end: Int?
        for character in marked {
            switch character {
            case "|":
                start = text.utf16.count
                end = start
            case "[":
                start = text.utf16.count
            case "]":
                end = text.utf16.count
            default:
                text.append(character)
            }
        }
        let location = start ?? text.utf16.count
        return (text, NSRange(location: location, length: (end ?? location) - location))
    }

    static func render(_ text: String, selection: NSRange) -> String {
        let string = text as NSString
        guard selection.location >= 0, selection.length >= 0, NSMaxRange(selection) <= string.length else {
            return "<選択が文章の外: \(text.debugDescription) \(selection)>"
        }
        let before = string.substring(to: selection.location)
        let after = string.substring(from: NSMaxRange(selection))
        if selection.length == 0 {
            return before + "|" + after
        }
        return before + "[" + string.substring(with: selection) + "]" + after
    }

    /// @note p0-893
    static func applying(_ edit: LineEdit, to text: String) -> String {
        let string = text as NSString
        guard NSMaxRange(edit.range) <= string.length else {
            return "<置き換える範囲が文章の外: \(text.debugDescription) \(edit.range)>"
        }
        let replaced = string.replacingCharacters(in: edit.range, with: edit.replacement)
        return render(replaced, selection: edit.selection)
    }
}

@MainActor
struct LineEditingTests {
    private func move(_ marked: String, _ direction: LineDirection) -> String? {
        let (text, selection) = MarkedText.parse(marked)
        return LineEditing.moveLines(in: text, selection: selection, direction: direction)
            .map { MarkedText.applying($0, to: text) }
    }

    private func duplicate(_ marked: String, _ direction: LineDirection) -> String {
        let (text, selection) = MarkedText.parse(marked)
        return MarkedText.applying(LineEditing.duplicateLines(in: text, selection: selection, direction: direction), to: text)
    }

    private func expand(_ marked: String) -> String? {
        let (text, selection) = MarkedText.parse(marked)
        return LineEditing.expandedLineSelection(in: text, selection: selection)
            .map { MarkedText.render(text, selection: $0) }
    }

    private func word(_ marked: String) -> String? {
        let (text, selection) = MarkedText.parse(marked)
        let attributed = NSAttributedString(string: text)
        return LineEditing.wordSelection(in: text, selection: selection) { attributed.doubleClick(at: $0) }
            .map { MarkedText.render(text, selection: $0) }
    }

    // MARK: - 行の移動

    @Test("AC-1: ⌥↑ / ⌥↓ でカーソルのある行が1つ上 / 下の行と入れ替わり、カーソルは移動した行の同じ位置に残る")
    func movesCursorLine() {
        #expect(move("one\ntw|o\nthree", .up) == "tw|o\none\nthree")
        #expect(move("one\ntw|o\nthree", .down) == "one\nthree\ntw|o")
        #expect(move("one\ntw|o\nthree\n", .down) == "one\nthree\ntw|o\n")
    }

    @Test("AC-1: 改行が \\r\\n の行も、カーソルは移動した行の同じ位置に残る")
    func movesCRLFLines() {
        #expect(move("a|\r\nb\r\n", .down) == "b\r\na|\r\n")
        #expect(move("a\r\nb|\r\n", .up) == "b|\r\na\r\n")
        #expect(move("a|\r\nb", .down) == "b\na|")
    }

    @Test("AC-2: 複数行にまたがる選択は、選択のかかった行がまとめて移動し、選択は同じ文字の上に残る")
    func movesSelectedLines() {
        #expect(move("o[ne\ntw]o\nthree", .down) == "three\no[ne\ntw]o")
        #expect(move("one\ntw[o\nthr]ee", .up) == "tw[o\nthr]ee\none")
        #expect(move("[a\nb\n]c", .down) == "c\n[a\nb]")
    }

    @Test("AC-2: 選択が行頭ちょうどで終わるときは、その行は動かさない")
    func selectionEndingAtLineStartExcludesThatLine() {
        #expect(move("o[ne\n]two\nthree", .down) == "two\no[ne\n]three")
        #expect(move("one\nt[wo\n]three", .up) == "t[wo\n]one\nthree")
        // @note p0-894
        #expect(LineEditing.coveredLines(in: "one\ntwo\nthree", selection: NSRange(location: 1, length: 3)) == NSRange(location: 0, length: 4))
        #expect(LineEditing.coveredLines(in: "one\ntwo\nthree", selection: NSRange(location: 1, length: 4)) == NSRange(location: 0, length: 8))
    }

    @Test("AC-3: いちばん上の行の ⌥↑ と、改行で終わらない最後の行の ⌥↓ は何もしない")
    func edgesDoNothing() {
        #expect(move("o|ne\ntwo", .up) == nil)
        #expect(move("[one\ntw]o", .up) == nil)
        #expect(move("one\ntw|o", .down) == nil)
        #expect(move("one\n[two]", .down) == nil)
    }

    @Test("AC-3: 最後の行を上に移しても行の間の改行が保たれ、改行で終わる文章は後ろの空の行と入れ替わる")
    func lastLineAndTrailingNewline() {
        #expect(move("a\nb|", .up) == "b|\na")
        #expect(move("|a\n", .down) == "\n|a")
        #expect(move("a|\n", .down) == "\na|")
    }

    @Test("AC-3: 改行まで選んだ行を改行で終わらない最後の行の下へ移すと、選択は移した行の中身(改行を除く)になる")
    func lineSelectionMovedBelowLastLineDropsNewline() {
        #expect(move("[a\n]b", .down) == "b\n[a]")
        #expect(move("[a\n]", .down) == "\n[a]")
    }

    // MARK: - 行の複製

    @Test("AC-4: ⇧⌥↓ は下の複製へカーソルが移り、⇧⌥↑ はカーソルが上側に残る")
    func duplicatesCursorLine() {
        #expect(duplicate("one\ntw|o\nthree", .down) == "one\ntwo\ntw|o\nthree")
        #expect(duplicate("one\ntw|o\nthree", .up) == "one\ntw|o\ntwo\nthree")
    }

    @Test("AC-4: 改行で終わらない最後の行・空の文章でも行が1つ増える")
    func duplicatesLastLineAndEmptyText() {
        #expect(duplicate("a\nb|", .down) == "a\nb\nb|")
        #expect(duplicate("a\nb|", .up) == "a\nb|\nb")
        #expect(duplicate("|", .down) == "\n|")
        #expect(duplicate("|", .up) == "|\n")
    }

    @Test("AC-4: 複数行の選択は、選択のかかった行をまとめて複製する")
    func duplicatesSelectedLines() {
        #expect(duplicate("o[ne\ntw]o\nthree", .down) == "one\ntwo\no[ne\ntw]o\nthree")
        #expect(duplicate("o[ne\ntw]o\nthree", .up) == "o[ne\ntw]o\none\ntwo\nthree")
    }

    // MARK: - 行ごとのコピー・切り取り・貼り付け

    @Test("AC-5: 選択なしのコピーは、カーソルのある行を改行ごと(改行で終わらない最後の行・空の文章は改行を足して)返す")
    func fullLineCopyText() {
        let cases: [(String, String)] = [
            ("alpha\nbe|ta\ngamma", "beta\n"),
            ("alpha\nbeta\ngam|ma", "gamma\n"),
            ("a\n|\nb", "\n"),
            ("a\n|", "\n"),
            ("|", "\n"),
        ]
        for (marked, expected) in cases {
            let (text, selection) = MarkedText.parse(marked)
            #expect(LineEditing.fullLineCopyText(in: text, cursor: selection.location) == expected, "\(marked.debugDescription)")
        }
    }

    @Test("AC-6: 選択なしの切り取りは、行を改行ごと消す。最後の行は前の行の改行ごと、1行だけなら中身だけ消える")
    func fullLineCut() {
        let cases: [(String, String, String)] = [
            ("alpha\nbe|ta\ngamma", "alpha\n|gamma", "beta\n"),
            ("a\nb|", "a|", "b\n"),
            ("a|bc", "|", "abc\n"),
            ("a\n|\nb", "a\n|b", "\n"),
        ]
        for (marked, expected, copied) in cases {
            let (text, selection) = MarkedText.parse(marked)
            let cut = LineEditing.fullLineCut(in: text, cursor: selection.location)
            #expect(cut.copiedText == copied, "\(marked.debugDescription)")
            #expect(cut.edit.map { MarkedText.applying($0, to: text) } == expected, "\(marked.debugDescription)")
        }
    }

    @Test("AC-6: 空の文章の切り取りは、改行1つをクリップボードに入れ、文章は変えない")
    func fullLineCutOfEmptyText() {
        let cut = LineEditing.fullLineCut(in: "", cursor: 0)
        #expect(cut.copiedText == "\n")
        #expect(cut.edit == nil)
    }

    @Test("AC-7: 行ごとの貼り付けは、カーソルが行の途中にあってもその行の上に1行として入り、カーソルは元の行の同じ位置に残る")
    func fullLinePaste() {
        let cases: [(String, String)] = [
            ("a\nb|c", "a\nx\nb|c"),
            ("a\n|bc", "a\nx\n|bc"),
            ("|", "x\n|"),
        ]
        for (marked, expected) in cases {
            let (text, selection) = MarkedText.parse(marked)
            let edit = LineEditing.fullLinePaste("x\n", in: text, cursor: selection.location)
            #expect(MarkedText.applying(edit, to: text) == expected, "\(marked.debugDescription)")
        }
    }

    @Test("AC-8: 行ごとの貼り付けになるのは、選択が無く、クリップボードに行ごとコピーの印があるときだけ")
    func fullLinePasteNeedsMarkAndNoSelection() {
        let marked: [NSPasteboard.PasteboardType] = [.string, LineEditing.fullLinePasteboardType]
        #expect(LineEditing.isFullLinePaste(selection: NSRange(location: 3, length: 0), pasteboardTypes: marked))
        #expect(!LineEditing.isFullLinePaste(selection: NSRange(location: 1, length: 2), pasteboardTypes: marked))
        #expect(!LineEditing.isFullLinePaste(selection: NSRange(location: 3, length: 0), pasteboardTypes: [.string]))
        #expect(!LineEditing.isFullLinePaste(selection: NSRange(location: 3, length: 0), pasteboardTypes: []))
    }

    // MARK: - 行・単語の選択

    @Test("AC-10: ⌘L はカーソルの行を改行まで選び、続けると下の行を加え、最後の行まで選んだら変わらない")
    func expandsLineSelection() {
        #expect(expand("one\ntw|o\nthree") == "one\n[two\n]three")
        #expect(expand("one\n[two\n]three") == "one\n[two\nthree]")
        #expect(expand("one\n[two\nthree]") == nil)
        #expect(expand("|one\ntwo") == "[one\n]two")
    }

    @Test("AC-10: 行の途中の選択は選択のかかった行全体に広がり、空の文章では何もしない")
    func expandsPartialSelectionToWholeLines() {
        #expect(expand("o[ne\ntw]o\nthree") == "[one\ntwo\n]three")
        #expect(expand("|") == nil)
    }

    @Test("AC-11: ⌘D はカーソルのある単語を選び、カーソルが単語の直後にあるときはその単語を選ぶ")
    func selectsWordAtCursor() {
        #expect(word("he|llo world") == "[hello] world")
        #expect(word("hello| world") == "[hello] world")
        #expect(word("hello |world") == "hello [world]")
        #expect(word("hello|") == "[hello]")
    }

    @Test("AC-11: 選択があるとき・空白や記号の中・空の文章では何もしない")
    func wordSelectionDoesNothing() {
        #expect(word("[hello] world") == nil)
        #expect(word("a |  b") == nil)
        #expect(word("--|- ***") == nil)
        #expect(word("|") == nil)
    }

    // MARK: - キーの判定

    @Test("AC-12: ⌥↑ / ⌥↓ / ⇧⌥↑ / ⇧⌥↓ は、fn・テンキーの印や Caps Lock があっても行の操作になる")
    func arrowCommandsIgnoreFunctionNumericPadAndCapsLock() {
        let cases: [(UInt16, NSEvent.ModifierFlags, LineArrowCommand)] = [
            (KeyCode.upArrow, [.option], .moveLines(.up)),
            (KeyCode.downArrow, [.option], .moveLines(.down)),
            (KeyCode.upArrow, [.option, .shift], .duplicateLines(.up)),
            (KeyCode.downArrow, [.option, .shift], .duplicateLines(.down)),
        ]
        let extras: [NSEvent.ModifierFlags] = [[], [.function, .numericPad], [.capsLock], [.function, .numericPad, .capsLock]]
        for (keyCode, modifiers, expected) in cases {
            for extra in extras {
                let input = PanelKeyInput(keyCode: keyCode, modifiers: modifiers.union(extra), hasMarkedText: false)
                #expect(LineEditing.arrowCommand(for: input) == expected, "\(input)")
            }
        }
    }

    @Test("AC-12: ほかの組み合わせ(修飾なし・⇧だけ・⌘や⌃を含む・←→・他のキー)と変換中は、行の操作にならない")
    func otherKeysAreNotArrowCommands() {
        let leftArrow: UInt16 = 123
        let rightArrow: UInt16 = 124
        let inputs = [
            PanelKeyInput(keyCode: KeyCode.upArrow, modifiers: [], hasMarkedText: false),
            PanelKeyInput(keyCode: KeyCode.downArrow, modifiers: [.function, .numericPad], hasMarkedText: false),
            PanelKeyInput(keyCode: KeyCode.upArrow, modifiers: [.shift], hasMarkedText: false),
            PanelKeyInput(keyCode: KeyCode.upArrow, modifiers: [.command], hasMarkedText: false),
            PanelKeyInput(keyCode: KeyCode.upArrow, modifiers: [.control, .option], hasMarkedText: false),
            PanelKeyInput(keyCode: KeyCode.upArrow, modifiers: [.command, .option], hasMarkedText: false),
            PanelKeyInput(keyCode: KeyCode.downArrow, modifiers: [.command, .option, .shift], hasMarkedText: false),
            PanelKeyInput(keyCode: leftArrow, modifiers: [.option], hasMarkedText: false),
            PanelKeyInput(keyCode: rightArrow, modifiers: [.option, .shift], hasMarkedText: false),
            PanelKeyInput(keyCode: KeyCode.escape, modifiers: [.option], hasMarkedText: false),
            PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: [.option], hasMarkedText: false),
            PanelKeyInput(keyCode: KeyCode.upArrow, modifiers: [.option], hasMarkedText: true),
            PanelKeyInput(keyCode: KeyCode.downArrow, modifiers: [.option, .shift], hasMarkedText: true),
        ]
        for input in inputs {
            #expect(LineEditing.arrowCommand(for: input) == nil, "\(input)")
        }
    }

    // MARK: - 境界

    @Test("AC-17: 空の文章・カーソルが文末・改行で終わる文章でも、規則どおりに振る舞う")
    func edgeTexts() {
        // @note p0-895
        #expect(move("|", .up) == nil)
        #expect(move("|", .down) == nil)
        #expect(expand("|") == nil)
        #expect(word("|") == nil)
        // @note p0-896
        #expect(move("one\ntwo|", .down) == nil)
        #expect(move("one\ntwo|", .up) == "two|\none")
        #expect(duplicate("one\ntwo|", .down) == "one\ntwo\ntwo|")
        #expect(expand("one\ntwo|") == "one\n[two]")
        // @note p0-897
        #expect(move("one\n|", .down) == nil)
        #expect(move("one\n|", .up) == "|\none")
        #expect(duplicate("one\n|", .down) == "one\n\n|")
        #expect(expand("one\n|") == nil)
        #expect(LineEditing.fullLineCopyText(in: "one\n", cursor: 4) == "\n")
        #expect(LineEditing.fullLineCut(in: "one\n", cursor: 4).edit.map { MarkedText.applying($0, to: "one\n") } == "one|")
    }

    @Test("AC-17: clamped は範囲内をそのまま返し、はみ出す範囲を文章の長さに収める")
    func clampedRange() {
        #expect(LineEditing.clamped(NSRange(location: 1, length: 2), toLength: 5) == NSRange(location: 1, length: 2))
        #expect(LineEditing.clamped(NSRange(location: 3, length: 5), toLength: 5) == NSRange(location: 3, length: 2))
        #expect(LineEditing.clamped(NSRange(location: 7, length: 2), toLength: 5) == NSRange(location: 5, length: 0))
        #expect(LineEditing.clamped(NSRange(location: 0, length: 0), toLength: 0) == NSRange(location: 0, length: 0))
    }

    @Test("AC-17: 文章の長さを超える選択・カーソルを渡しても落ちず、結果は文章の中に収まる")
    func outOfRangeSelection() {
        let text = "ab\ncd"
        let length = (text as NSString).length
        let selections = [
            NSRange(location: 1, length: 10),
            NSRange(location: 9, length: 0),
            NSRange(location: 9, length: 3),
        ]
        for selection in selections {
            let label = "\(selection)"
            for direction in [LineDirection.up, .down] {
                if let edit = LineEditing.moveLines(in: text, selection: selection, direction: direction) {
                    expectFits(edit, in: text, label)
                }
                expectFits(LineEditing.duplicateLines(in: text, selection: selection, direction: direction), in: text, label)
            }
            if let range = LineEditing.expandedLineSelection(in: text, selection: selection) {
                expectFits(range, inLength: length, label)
            }
            let attributed = NSAttributedString(string: text)
            if let range = LineEditing.wordSelection(in: text, selection: selection, wordRange: { attributed.doubleClick(at: $0) }) {
                expectFits(range, inLength: length, label)
            }
            _ = LineEditing.coveredLines(in: text, selection: selection)
        }
        #expect(LineEditing.fullLineCopyText(in: text, cursor: 99) == "cd\n")
        if let edit = LineEditing.fullLineCut(in: text, cursor: 99).edit {
            expectFits(edit, in: text, "cut 99")
        }
        expectFits(LineEditing.fullLinePaste("x\n", in: text, cursor: 99), in: text, "paste 99")
    }

    @Test("AC-17: どの選択範囲・カーソルから始めても、操作後の選択範囲は操作後の文章に収まる")
    func everySelectionStaysInsideText() {
        let texts = ["", "a", "a\n", "a\nb", "ab\nc", "a\n\nb\n", "\n", "a\r\nb\r\n"]
        for text in texts {
            let length = (text as NSString).length
            let attributed = NSAttributedString(string: text)
            for location in 0...length {
                for selectionLength in 0...(length - location) {
                    let selection = NSRange(location: location, length: selectionLength)
                    let label = "\(text.debugDescription) \(selection)"
                    for direction in [LineDirection.up, .down] {
                        if let edit = LineEditing.moveLines(in: text, selection: selection, direction: direction) {
                            expectFits(edit, in: text, "move \(direction) \(label)")
                        }
                        let duplicated = LineEditing.duplicateLines(in: text, selection: selection, direction: direction)
                        expectFits(duplicated, in: text, "duplicate \(direction) \(label)")
                    }
                    if let range = LineEditing.expandedLineSelection(in: text, selection: selection) {
                        expectFits(range, inLength: length, "expand \(label)")
                    }
                    if let selectedWord = LineEditing.wordSelection(in: text, selection: selection, wordRange: { attributed.doubleClick(at: $0) }) {
                        expectFits(selectedWord, inLength: length, "word \(label)")
                    }
                }
                let label = "\(text.debugDescription) cursor \(location)"
                if let edit = LineEditing.fullLineCut(in: text, cursor: location).edit {
                    expectFits(edit, in: text, "cut \(label)")
                }
                expectFits(LineEditing.fullLinePaste("x\n", in: text, cursor: location), in: text, "paste \(label)")
            }
        }
    }

    /// @note p0-898
    private func expectFits(_ edit: LineEdit, in text: String, _ label: String) {
        let string = text as NSString
        let rangeFits = edit.range.location >= 0 && edit.range.length >= 0 && NSMaxRange(edit.range) <= string.length
        #expect(rangeFits, "置き換える範囲: \(label) \(edit.range)")
        guard rangeFits else { return }
        let replacedLength = (string.replacingCharacters(in: edit.range, with: edit.replacement) as NSString).length
        expectFits(edit.selection, inLength: replacedLength, label)
    }

    private func expectFits(_ range: NSRange, inLength length: Int, _ label: String) {
        #expect(range.location >= 0 && range.length >= 0 && NSMaxRange(range) <= length, "選択: \(label) \(range) / 長さ \(length)")
    }
}
