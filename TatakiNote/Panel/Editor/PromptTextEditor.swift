import AppKit
import SwiftUI

/// パネルの入力欄。
final class PromptTextView: EditorTextView {
    var onKeyInput: ((PanelKeyInput) -> Bool)?

    /// 文章が変わったとき(打つ・置換・取り消し・別の文章の入れ替え)に呼ぶ。
    var onStringChange: (() -> Void)?

    /// 選択が確定して変わったときに呼ぶ。
    var onSelectionChange: (() -> Void)?

    /// 今ハイライトしている一致。
    private(set) var findHighlights: [FindHighlight] = []

    private lazy var baseSelectedTextAttributes = selectedTextAttributes
    private var findBorderView: FindBorderView?
    private var undoObservers: [NSObjectProtocol] = []
    private weak var observedUndoManager: UndoManager?

    /// 余白を足す前の textContainerInset。
    var baseContainerInset: NSSize = .zero {
        didSet { applyContainerInset() }
    }

    /// 最後の行の下に空ける高さ。
    var bottomPadding: CGFloat = 0 {
        didSet { applyContainerInset() }
    }

    // MARK: - 余白

    override var textContainerOrigin: NSPoint {
        NSPoint(x: super.textContainerOrigin.x, y: baseContainerInset.height)
    }

    override func scrollRangeToVisible(_ range: NSRange) {
        super.scrollRangeToVisible(range)
        revealBottomPadding(for: range)
    }

    override func didChangeText() {
        super.didChangeText()
        revealBottomPadding(for: selectedRange())
        findBorderView?.needsDisplay = true
        observeUndoManagerIfNeeded()
        onStringChange?()
    }

    isolated deinit {
        removeUndoObservers()
    }

    private func observeUndoManagerIfNeeded() {
        guard let undoManager, undoManager !== observedUndoManager else { return }
        removeUndoObservers()
        observedUndoManager = undoManager
        for name in [Notification.Name.NSUndoManagerDidUndoChange, Notification.Name.NSUndoManagerDidRedoChange] {
            let observer = NotificationCenter.default.addObserver(
                forName: name,
                object: undoManager,
                queue: nil
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.onStringChange?() }
            }
            undoObservers.append(observer)
        }
    }

    private func removeUndoObservers() {
        for observer in undoObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        undoObservers = []
        observedUndoManager = nil
    }

    override var string: String {
        didSet { onStringChange?() }
    }

    override func setSelectedRanges(
        _ ranges: [NSValue],
        affinity: NSSelectionAffinity,
        stillSelecting stillSelectingFlag: Bool
    ) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        if !findHighlights.isEmpty {
            refreshSelectionAppearance()
        }
        if !stillSelectingFlag {
            onSelectionChange?()
        }
    }

    /// ハイライトの記録を入れ替える。
    func storeFindHighlights(_ highlights: [FindHighlight]) {
        findHighlights = highlights
        updateFindBorder()
        refreshSelectionAppearance()
    }

    private func updateFindBorder() {
        guard let current = findHighlights.first(where: \.isCurrent)?.range else {
            findBorderView?.range = nil
            return
        }
        let border = findBorderView ?? makeFindBorderView()
        border.frame = bounds
        border.range = current
    }

    private func makeFindBorderView() -> FindBorderView {
        let border = FindBorderView(frame: bounds)
        addSubview(border)
        findBorderView = border
        return border
    }

    /// 今の一致が選択と重なるときだけ、選択の塗りを消す。
    func refreshSelectionAppearance() {
        let hidesFill = FindHighlighter.isCurrentSelected(findHighlights, selection: selectedRange())
        selectedTextAttributes = FindHighlighter.selectedTextAttributes(
            base: baseSelectedTextAttributes,
            hidesSelectionFill: hidesFill
        )
        needsDisplay = true
    }

    private func applyContainerInset() {
        textContainerInset = EditorBottomPadding.containerInset(base: baseContainerInset, padding: bottomPadding)
        invalidateTextContainerOrigin()
        sizeToFit()
    }

    private func revealBottomPadding(for range: NSRange) {
        guard bottomPadding > 0, let window else { return }
        let text = string as NSString
        guard EditorBottomPadding.isInLastLine(range, of: text) else { return }
        let end = min(NSMaxRange(range), text.length)
        let screenRect = firstRect(forCharacterRange: NSRange(location: end, length: 0), actualRange: nil)
        guard screenRect.height > 0 else { return }
        let caretRect = convert(window.convertFromScreen(screenRect), from: nil)
        let rect = EditorBottomPadding.revealRect(
            caretRect: caretRect,
            documentMaxY: caretRect.maxY + baseContainerInset.height + bottomPadding,
            visibleHeight: visibleRect.height,
            padding: bottomPadding,
            isInLastLine: true
        )
        scrollToVisible(rect)
    }

    // MARK: - キー操作

    override func keyDown(with event: NSEvent) {
        let input = PanelKeyInput(event: event, hasMarkedText: hasMarkedText())
        if onKeyInput?(input) == true {
            return
        }
        if let command = LineEditing.arrowCommand(for: input) {
            performLineArrowCommand(command)
            return
        }
        super.keyDown(with: event)
    }

    override func handleKeyEquivalent(_ event: NSEvent) -> EditorKeyEquivalentResult {
        let input = PanelKeyInput(event: event, hasMarkedText: false)
        if onKeyInput?(input) == true {
            return .handled
        }
        if event.keyCode == KeyCode.returnKey || event.keyCode == KeyCode.keypadEnter {
            if PanelKeyResolver.insertsNewlineExplicitly(for: input) {
                insertNewline(nil)
                return .handled
            }
            return .passToSystem
        }
        let modifiers = event.modifierFlags.intersection(PanelShortcut.relevantModifiers)
        switch EditorKeyCommand.command(modifiers: modifiers, character: input.characters) {
        case .selectWord:
            selectWordAtCursor()
            return .handled
        case .selectLine:
            expandLineSelection()
            return .handled
        default:
            return .notHandled
        }
    }

    override func copyCommand() {
        copyLineOrSelection()
    }

    override func cutCommand() {
        cutLineOrSelection()
    }

    override func pasteCommand() {
        pasteLineOrClipboard()
    }

    // MARK: - 行・単語の操作

    func performLineArrowCommand(_ command: LineArrowCommand) {
        switch command {
        case .moveLines(let direction): moveLines(direction)
        case .duplicateLines(let direction): duplicateLines(direction)
        }
    }

    func moveLines(_ direction: LineDirection) {
        guard let edit = LineEditing.moveLines(in: string, selection: selectedRange(), direction: direction) else { return }
        apply(edit)
    }

    func duplicateLines(_ direction: LineDirection) {
        apply(LineEditing.duplicateLines(in: string, selection: selectedRange(), direction: direction))
    }

    func expandLineSelection() {
        guard let range = LineEditing.expandedLineSelection(in: string, selection: selectedRange()) else { return }
        selectAndReveal(range)
    }

    func selectWordAtCursor() {
        let word = LineEditing.wordSelection(in: string, selection: selectedRange()) { position in
            selectionRange(forProposedRange: NSRange(location: position, length: 1), granularity: .selectByWord)
        }
        guard let word else { return }
        selectAndReveal(word)
    }

    func copyLineOrSelection() {
        let selection = selectedRange()
        guard selection.length == 0 else {
            copy(nil)
            return
        }
        writeFullLine(LineEditing.fullLineCopyText(in: string, cursor: selection.location))
    }

    func cutLineOrSelection() {
        let selection = selectedRange()
        guard selection.length == 0 else {
            cut(nil)
            return
        }
        let lineCut = LineEditing.fullLineCut(in: string, cursor: selection.location)
        writeFullLine(lineCut.copiedText)
        if let edit = lineCut.edit {
            apply(edit)
        }
    }

    func pasteLineOrClipboard() {
        let selection = selectedRange()
        if LineEditing.isFullLinePaste(selection: selection, pasteboardTypes: pasteboard.types ?? []),
           let line = pasteboard.string(forType: .string) {
            apply(LineEditing.fullLinePaste(line, in: string, cursor: selection.location))
            return
        }
        paste(nil)
    }

    private func writeFullLine(_ line: String) {
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, LineEditing.fullLinePasteboardType], owner: nil)
        pasteboard.setString(line, forType: .string)
        pasteboard.setString("1", forType: LineEditing.fullLinePasteboardType)
    }

    private func apply(_ edit: LineEdit) {
        breakUndoCoalescing()
        undoManager?.beginUndoGrouping()
        let changed = shouldChangeText(in: edit.range, replacementString: edit.replacement)
        if changed {
            textStorage?.replaceCharacters(
                in: edit.range,
                with: NSAttributedString(string: edit.replacement, attributes: typingAttributes)
            )
            didChangeText()
        }
        undoManager?.endUndoGrouping()
        breakUndoCoalescing()
        guard changed else { return }
        selectAndReveal(edit.selection)
    }

    private func selectAndReveal(_ range: NSRange) {
        let selection = LineEditing.clamped(range, toLength: (string as NSString).length)
        setSelectedRange(selection)
        scrollRangeToVisible(selection)
    }
}

struct PromptTextEditor: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: Int
    let font: NSFont
    var placeholder: String = ""
    var bottomPaddingLines: Int = 0
    let onKeyInput: (PanelKeyInput) -> Bool
    var findRegistry: FindEditorRegistry?
    var onFindTextChange: () -> Void = {}
    var onFindSelectionChange: () -> Void = {}

    typealias Coordinator = EditorTextCoordinator

    private var bottomPadding: CGFloat {
        EditorBottomPadding.height(lines: bottomPaddingLines, lineHeight: EditorBottomPadding.lineHeight(for: font))
    }

    func makeCoordinator() -> Coordinator {
        EditorTextCoordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PromptTextView()
        textView.delegate = context.coordinator
        textView.onKeyInput = onKeyInput
        findRegistry?.editor = textView
        textView.configurePlainTextEditing(
            textContainerInset: PanelMetrics.textContainerInset,
            accessibilityIdentifier: "promptPanel.textView"
        )
        textView.baseContainerInset = PanelMetrics.textContainerInset
        textView.applyFont(font)
        textView.bottomPadding = bottomPadding
        textView.placeholder = placeholder
        textView.string = text
        textView.onStringChange = onFindTextChange
        textView.onSelectionChange = onFindSelectionChange
        return EditorTextView.scrollView(containing: textView, backgroundColor: nil)
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PromptTextView else { return }
        textView.onKeyInput = onKeyInput
        textView.onStringChange = onFindTextChange
        textView.onSelectionChange = onFindSelectionChange
        findRegistry?.editor = textView
        context.coordinator.text = $text
        textView.applyFont(font)
        if textView.bottomPadding != bottomPadding {
            textView.bottomPadding = bottomPadding
        }
        if textView.placeholder != placeholder {
            textView.placeholder = placeholder
        }
        context.coordinator.syncText(text, to: textView)
        context.coordinator.focusIfRequested(focusRequest, textView: textView)
    }
}
