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

    /// 今の見え方の設定。
    var readability: EditorReadability = .standard

    /// 今のフォントと見え方の設定から決めた配置。フォントが無い間は nil。
    var textLayout: EditorTextLayout?

    /// 変換中に付け直せなかった属性が残っているか。
    var pendingRestyle = false

    /// 配置が変わって、新しく打つ文字の属性を入れ直す必要があるか。
    var needsTypingAttributes = false

    /// 余白を足す前の textContainerInset。
    var baseContainerInset: NSSize = .zero {
        didSet { applyContainerInset() }
    }

    /// 最後の行の下に空ける高さ。
    var bottomPadding: CGFloat = 0 {
        didSet { applyContainerInset() }
    }

    /// 自前のカーソルを描く view。システムのカーソルだけを使っている間は作られない。
    var caretView: EditorCaretView?

    /// 自前のカーソルの点滅の時間。
    var caretBlinkPeriods = EditorCaretBlink.Periods.system()

    /// 自前のカーソルを描くときに使う、元のカーソルの色。
    lazy var baseInsertionPointColor = insertionPointColor

    /// 入力欄がある窓がキーか。
    var isCaretWindowKey = false

    /// 入力欄がファーストレスポンダか。
    var isCaretFirstResponder = false

    /// 窓がキーになる・外れる通知の見張り。
    var caretWindowObservers: [NSObjectProtocol] = []

    /// 今いる行のハイライトの矩形(入力欄の座標)。出さないときは nil。
    private(set) var currentLineHighlightRect: CGRect?

    /// URL を畳んで色を付けるか。
    var foldsURLs = false {
        didSet {
            if foldsURLs != oldValue {
                refreshURLFolds()
            }
        }
    }

    /// 今の URL の見え方。
    var urlPresentations: [EditorURLPresentation] = []

    /// URL の付け直しの中か。
    var isApplyingURLFolds = false

    /// 前回 `textStorage` に付けた隠す字間。
    var appliedHiddenKerns: [EditorHiddenKern] = []

    /// 前回 rendering 属性で色を付けた範囲。
    var appliedURLColorRanges: [NSRange] = []

    /// URL を開く役。
    var urlOpener: EditorURLOpening = WorkspaceEditorURLOpener()

    /// 見え方の全 URL の矩形(入力欄の座標)。
    var urlHitAreas: [EditorURLHitArea] = []

    /// 畳んだ URL に付けた吹き出しのタグ。
    var urlToolTipTags: [NSView.ToolTipTag] = []

    /// 畳んだ URL の吹き出しの文字を返す持ち主。
    lazy var urlToolTipOwner = EditorURLToolTipOwner { [weak self] point in
        self?.urlToolTip(at: point)
    }

    /// 今、マウスカーソルを指にしているか。
    var isShowingURLPointingHand = false

    /// マウスカーソルを設定する処理。
    var urlCursorApplier: (NSCursor) -> Void = { $0.set() }

    /// マウスカーソルのための追跡の領域。
    var urlCursorTrackingArea: NSTrackingArea?

    // MARK: - URL のマウスカーソル

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateURLCursor(at: convert(event.locationInWindow, from: nil), modifiers: event.modifierFlags)
    }

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        guard let window else { return }
        updateURLCursor(at: convert(window.mouseLocationOutsideOfEventStream, from: nil), modifiers: event.modifierFlags)
    }

    override func cursorUpdate(with event: NSEvent) {
        super.cursorUpdate(with: event)
        updateURLCursor(at: convert(event.locationInWindow, from: nil), modifiers: event.modifierFlags)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isShowingURLPointingHand = false
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard urlCursorTrackingArea == nil else { return }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        urlCursorTrackingArea = area
    }

    // MARK: - URL のクリックとメニュー

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if handleURLClick(at: point, modifiers: event.modifierFlags) {
            return
        }
        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let url = urlForContextMenu(at: convert(event.locationInWindow, from: nil))
        let menu = super.menu(for: event)
        guard let url else { return menu }
        return urlContextMenu(base: menu, url: url)
    }

    // MARK: - 今いる行のハイライト

    /// 設定・選択・文章・幅から、今いる行のハイライトの矩形を決め直し、前の矩形と今の矩形を描き直す。
    func refreshCurrentLineHighlight() {
        let rect = makeCurrentLineHighlightRect()
        guard rect != currentLineHighlightRect else { return }
        let previous = currentLineHighlightRect
        currentLineHighlightRect = rect
        for changed in [previous, rect] {
            if let changed {
                setNeedsDisplay(changed.insetBy(dx: -1, dy: -1))
            }
        }
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        if let highlight = currentLineHighlightRect, highlight.intersects(rect) {
            EditorCurrentLine.color.setFill()
            highlight.intersection(rect).fill(using: .sourceOver)
        }
        drawURLEllipses(in: rect)
        drawURLLinkIcons(in: rect)
    }

    // MARK: - 余白

    override var textContainerOrigin: NSPoint {
        NSPoint(x: super.textContainerOrigin.x, y: baseContainerInset.height)
    }

    override func scrollRangeToVisible(_ range: NSRange) {
        super.scrollRangeToVisible(range)
        revealBottomPadding(for: range)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.size.width
        super.setFrameSize(newSize)
        if widthChanged {
            handleWidthChange()
        }
    }

    // MARK: - 変換とフォント

    override func applyFont(_ font: NSFont) {
        super.applyFont(font)
        if textLayout?.font != self.font {
            refreshTextLayout()
        }
    }

    override func unmarkText() {
        super.unmarkText()
        if pendingRestyle {
            restyleText()
        }
        refreshCaret()
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        ensureLayoutBeforeMarkedText()
        refreshCaret()
    }

    override func didChangeText() {
        super.didChangeText()
        restyleText()
        refreshCaret()
        revealBottomPadding(for: selectedRange())
        findBorderView?.needsDisplay = true
        observeUndoManagerIfNeeded()
        onStringChange?()
    }

    isolated deinit {
        removeUndoObservers()
        removeCaretWindowObservers()
    }

    // MARK: - カーソルの出来事

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            setCaretFocus(isKeyWindow: window?.isKeyWindow ?? false, isFirstResponder: true)
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            setCaretFocus(isKeyWindow: isCaretWindowKey, isFirstResponder: false)
        }
        return resigned
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeCaretWindow()
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
                MainActor.assumeIsolated {
                    self?.restyleText()
                    self?.onStringChange?()
                }
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
        didSet {
            restyleText()
            refreshCaret()
            onStringChange?()
        }
    }

    override func setSelectedRanges(
        _ ranges: [NSValue],
        affinity: NSSelectionAffinity,
        stillSelecting stillSelectingFlag: Bool
    ) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        refreshCaret()
        if !stillSelectingFlag, !isApplyingURLFolds {
            refreshURLFolds()
        }
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
        refreshURLFolds()
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

    func applyContainerInset() {
        textContainerInset = EditorBottomPadding.containerInset(base: baseContainerInset, padding: bottomPadding)
        invalidateTextContainerOrigin()
        sizeToFit()
    }

    private func revealBottomPadding(for range: NSRange) {
        guard bottomPadding > 0, let window else { return }
        let text = string as NSString
        guard EditorBottomPadding.isInLastLine(range, of: text) else { return }
        let end = min(NSMaxRange(range), text.length)
        for _ in 0..<Self.maxRevealPasses {
            let previousMaxY = bounds.maxY
            guard scrollBottomPaddingIntoView(at: end, in: window) else { return }
            textLayoutManager?.textViewportLayoutController.layoutViewport()
            sizeToFit()
            if bounds.maxY == previousMaxY { return }
        }
    }

    private static let maxRevealPasses = 4

    private func scrollBottomPaddingIntoView(at end: Int, in window: NSWindow) -> Bool {
        let screenRect = firstRect(forCharacterRange: NSRange(location: end, length: 0), actualRange: nil)
        guard screenRect.height > 0 else { return false }
        let caretRect = convert(window.convertFromScreen(screenRect), from: nil)
        sizeToFit()
        let rect = EditorBottomPadding.revealRect(
            caretRect: caretRect,
            documentMaxY: max(caretRect.maxY + baseContainerInset.height + bottomPadding, bounds.maxY),
            visibleHeight: visibleRect.height,
            padding: bottomPadding,
            isInLastLine: true
        )
        scrollToVisible(rect)
        return true
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
    var readability: EditorReadability = .standard
    var foldsURLs: Bool = false
    let onKeyInput: (PanelKeyInput) -> Bool
    var findRegistry: FindEditorRegistry?
    var onFindTextChange: () -> Void = {}
    var onFindSelectionChange: () -> Void = {}

    typealias Coordinator = EditorTextCoordinator

    private var bottomPadding: CGFloat {
        EditorBottomPadding.height(
            lines: bottomPaddingLines,
            lineHeight: EditorTextLayout(font: font, readability: readability).lineHeight
        )
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
        textView.applyReadability(readability)
        textView.foldsURLs = foldsURLs
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
        textView.applyReadability(readability)
        textView.foldsURLs = foldsURLs
        let bottomPadding = bottomPadding
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
