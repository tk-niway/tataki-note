import AppKit

extension PromptTextView {
    // MARK: - 見え方の設定

    /// 見え方の設定を入力欄に当てる。前と同じなら何もしない。
    func applyReadability(_ readability: EditorReadability) {
        guard readability != self.readability || textLayout == nil else { return }
        self.readability = readability
        refreshTextLayout()
        refreshCurrentLineHighlight()
    }

    /// 今のフォントと設定から配置を作り直し、違っていれば余白と段落の属性を付け直す。
    func refreshTextLayout() {
        let layout = font.map { EditorTextLayout(font: $0, readability: readability) }
        guard layout != textLayout else { return }
        textLayout = layout
        needsTypingAttributes = true
        restyleText()
        updateCaretAppearance()
        refreshCurrentLineHighlight()
    }

    /// 文章の段落ごとの属性を付け直す。変換中は確定の後まで保留する。
    func restyleText() {
        guard !hasMarkedText() else {
            pendingRestyle = true
            return
        }
        pendingRestyle = false
        guard let layout = textLayout, let storage = textStorage else { return }
        if needsTypingAttributes {
            needsTypingAttributes = false
            applyTypingAttributes(of: layout)
        }
        EditorParagraphStyler(layout: layout, lineWidth: lineWidth).apply(to: storage)
    }

    /// 入力欄の幅が変わったときに、段落の属性とカーソルを決め直す。
    func handleWidthChange() {
        restyleText()
        refreshCaret()
    }

    // MARK: - カーソル

    /// システムのカーソルを消し、自前のカーソルを今の設定に合わせて描く。
    func updateCaretAppearance() {
        let baseColor = baseInsertionPointColor ?? .controlTextColor
        insertionPointColor = .clear
        let view = caretView ?? makeCaretView()
        view.isHidden = false
        view.color = baseColor
        view.shape = readability.caretShape
        refreshCaret()
    }

    /// カーソルの位置が変わりうる出来事の後に、自前のカーソルの位置と点滅を直す。
    func refreshCaret() {
        refreshCurrentLineHighlight()
        guard let view = caretView else { return }
        view.caretRect = currentCaretRect()
        let isActive = EditorCaretGeometry.isCaretActive(
            isKeyWindow: isCaretWindowKey,
            isFirstResponder: isCaretFirstResponder,
            selectionLength: selectedRange().length
        )
        if !isActive {
            view.send(.deactivate)
        } else if view.blink.phase == .hidden {
            view.send(.activate)
        } else {
            view.send(.reset)
        }
    }

    /// 窓のキーの状態と入力欄のフォーカスの状態を受け取って、点滅を直す。
    func setCaretFocus(isKeyWindow: Bool, isFirstResponder: Bool) {
        isCaretWindowKey = isKeyWindow
        isCaretFirstResponder = isFirstResponder
        refreshCaret()
    }

    /// 窓がキーになる・外れる通知を見張り直す。
    func observeCaretWindow() {
        removeCaretWindowObservers()
        guard let window else {
            setCaretFocus(isKeyWindow: false, isFirstResponder: false)
            return
        }
        for (name, isKey) in [(NSWindow.didBecomeKeyNotification, true), (NSWindow.didResignKeyNotification, false)] {
            let observer = NotificationCenter.default.addObserver(forName: name, object: window, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.setCaretFocus(isKeyWindow: isKey, isFirstResponder: self.isCaretFirstResponder)
                }
            }
            caretWindowObservers.append(observer)
        }
        setCaretFocus(isKeyWindow: window.isKeyWindow, isFirstResponder: window.firstResponder === self)
    }

    /// 窓の通知の見張りをやめる。
    func removeCaretWindowObservers() {
        for observer in caretWindowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        caretWindowObservers = []
    }

    /// カーソルの位置(長さ 0 の範囲)の枠。入力欄の座標。取れなければ nil。
    func caretSegmentRect(at location: Int) -> CGRect? {
        segmentRects(for: NSRange(location: location, length: 0)).first
    }

    private func makeCaretView() -> EditorCaretView {
        let view = EditorCaretView(frame: bounds, periods: caretBlinkPeriods)
        addSubview(view)
        caretView = view
        return view
    }

    /// 今いる行のハイライトの矩形(入力欄の座標)。オフ・変換中でなく選択がある・取れないときは nil。
    func makeCurrentLineHighlightRect() -> CGRect? {
        guard readability.highlightsCurrentLine, let layout = textLayout, let container = textContainer else { return nil }
        let selection = selectedRange()
        guard let range = EditorCurrentLine.paragraphRange(
            in: string as NSString,
            selection: selection,
            markedRange: hasMarkedText() ? markedRange() : nil,
            isEnabled: readability.highlightsCurrentLine
        ) else { return nil }
        let lineRects = range.length > 0 ? FindHighlighter.rects(for: range, in: self) : []
        let caret = lineRects.isEmpty
            ? (caretSegmentRect(at: selection.location) ?? fallbackCaretRect(at: selection.location, layout: layout))
            : nil
        return EditorCurrentLine.rect(
            lineRects: lineRects,
            caretRect: caret,
            containerMinX: textContainerOrigin.x,
            containerWidth: container.size.width
        )
    }

    private func currentCaretRect() -> CGRect? {
        guard let layout = textLayout else { return nil }
        let selection = selectedRange()
        guard selection.length == 0, selection.location != NSNotFound else { return nil }
        let caret = caretSegmentRect(at: selection.location)
            ?? fallbackCaretRect(at: selection.location, layout: layout)
        return EditorCaretGeometry.rect(
            shape: readability.caretShape,
            barWidth: EditorCaretGeometry.barWidth,
            caretRect: caret,
            textHeight: layout.baseLineHeight,
            characterRect: characterRect(at: selection.location),
            fallbackWidth: layout.fullWidthAdvance / 2
        )
    }

    private func characterRect(at location: Int) -> CGRect? {
        let text = string as NSString
        guard location >= 0, location < text.length else { return nil }
        let range = text.rangeOfComposedCharacterSequence(at: location)
        guard text.substring(with: range).rangeOfCharacter(from: .newlines) == nil else { return nil }
        return FindHighlighter.rects(for: range, in: self).first
    }

    private func fallbackCaretRect(at location: Int, layout: EditorTextLayout) -> CGRect {
        let text = string as NSString
        var previousLineMaxY: CGFloat?
        if location > 0, location == text.length {
            let last = text.rangeOfComposedCharacterSequence(at: location - 1)
            if text.substring(with: last).rangeOfCharacter(from: .newlines) != nil {
                previousLineMaxY = segmentRects(for: last).last?.maxY
            }
        }
        return EditorCaretGeometry.fallbackCaretRect(
            previousLineMaxY: previousLineMaxY,
            containerOrigin: textContainerOrigin,
            lineFragmentPadding: textContainer?.lineFragmentPadding ?? EditorTextLayout.lineFragmentPadding,
            textHeight: layout.baseLineHeight,
            lineSpacing: layout.lineSpacing,
            paragraphSpacing: layout.paragraphSpacing
        )
    }

    private func segmentRects(for range: NSRange) -> [CGRect] {
        let origin = textContainerOrigin
        var frames: [CGRect] = []
        if let layoutManager = textLayoutManager, let contentManager = layoutManager.textContentManager {
            let start = contentManager.documentRange.location
            guard let lower = contentManager.location(start, offsetBy: range.location),
                  let upper = contentManager.location(lower, offsetBy: range.length),
                  let textRange = NSTextRange(location: lower, end: upper)
            else { return [] }
            layoutManager.enumerateTextSegments(in: textRange, type: .selection, options: []) { _, frame, _, _ in
                frames.append(frame)
                return true
            }
        } else if let layoutManager, let container = textContainer {
            frames = legacySegmentFrames(for: range, layoutManager: layoutManager, container: container)
        }
        return frames
            .map { $0.offsetBy(dx: origin.x, dy: origin.y) }
            .filter { $0.height > 0 && $0.origin.x.isFinite && $0.origin.y.isFinite && $0.width.isFinite && $0.height.isFinite }
    }

    private func legacySegmentFrames(for range: NSRange, layoutManager: NSLayoutManager, container: NSTextContainer) -> [CGRect] {
        let length = (string as NSString).length
        guard length > 0 else { return [] }
        let index = min(range.location, length - 1)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: index, length: max(range.length, 1)), actualCharacterRange: nil)
        var frame = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
        if range.length == 0 {
            if range.location > index {
                frame.origin.x = frame.maxX
            }
            frame.size.width = 0
        }
        return [frame]
    }

    private var lineWidth: CGFloat {
        max(0, bounds.width - 2 * baseContainerInset.width - 2 * EditorTextLayout.lineFragmentPadding)
    }

    private func applyTypingAttributes(of layout: EditorTextLayout) {
        let style = layout.paragraphStyle(headIndent: 0)
        typingAttributes[.paragraphStyle] = style
        if layout.kern > 0 {
            typingAttributes[.kern] = layout.kern
        } else {
            typingAttributes[.kern] = nil
        }
        defaultParagraphStyle = style
    }
}
