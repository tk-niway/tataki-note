import AppKit

extension PromptTextView {
    /// rendering 属性の色が文章の変更で文字と一緒に動くか。
    static let urlColorsFollowText = true

    // MARK: - 畳む・開く

    /// 文章・選択・検索の一致・設定から URL の見え方を決め直し、変わった所だけ隠す字間と色を付け直す。
    func refreshURLFolds(textDidChange: Bool = false) {
        observeTextStorageIfNeeded()
        guard !hasMarkedText() else { return }
        let wasApplyingURLFolds = isApplyingURLFolds
        isApplyingURLFolds = true
        defer { isApplyingURLFolds = wasApplyingURLFolds }
        defer { refreshURLHitAreas() }

        urlFoldRefreshCount += 1
        let text = string as NSString
        let selection = selectedRange()
        lastURLFoldSelection = selection
        let change = urlIndex.update(in: text)

        guard foldsURLs,
              let layout = textLayout,
              let storage = textStorage,
              let layoutManager = textLayoutManager,
              let contentManager = layoutManager.textContentManager
        else {
            clearURLFolds()
            urlPresentations = urlIndex.urls.map { EditorURLPresentation(url: $0, fold: nil) }
            needsFullURLRestyle = true
            lastURLFoldUpdate = EditorURLFoldUpdate(redetectedRange: change.redetectedRange, restyleRanges: [], recolorRanges: [])
            return
        }

        let presentations = EditorURLPresentation.make(
            urls: urlIndex.urls,
            selection: selection,
            findRanges: findHighlights.map(\.range)
        )
        let previous = EditorURLRestyleScope.shifted(urlPresentations, through: change.edits)
        let restyleRanges = EditorURLRestyleScope.restyleRanges(
            previous: previous,
            current: presentations,
            redetectedRange: change.redetectedRange,
            isWhole: needsFullURLRestyle || change.isWhole,
            textLength: text.length
        )
        urlPresentations = presentations
        needsFullURLRestyle = false

        hasURLFoldMarks = presentations.contains { $0.fold != nil }
        var storageChanged = false
        if !restyleRanges.isEmpty {
            let styler = EditorURLFoldStyler(font: layout.font, baseKern: layout.kern)
            let caretMinYBefore = selection.location == NSNotFound ? nil : caretSegmentRect(at: selection.location)?.minY
            for range in restyleRanges {
                let overlapping = presentations.filter { NSIntersectionRange($0.url.range, range).length > 0 }
                let kerns = styler.hiddenKerns(for: overlapping, in: text)
                if styler.apply(kerns, to: storage, in: range) {
                    storageChanged = true
                }
            }
            if storageChanged {
                layoutManager.ensureLayout(for: layoutManager.documentRange)
                keepCaretLineInPlace(selection: selection, minYBefore: caretMinYBefore)
                refreshCaret()
            }
        }

        let recolorRanges = EditorURLRestyleScope.recolorRanges(
            restyleRanges: restyleRanges,
            change: change,
            textLength: text.length,
            colorsFollowText: Self.urlColorsFollowText
        )
        if !recolorRanges.isEmpty {
            applyURLColors(
                presentations,
                in: recolorRanges,
                length: text.length,
                layoutManager: layoutManager,
                contentManager: contentManager
            )
        }

        appliedURLColorRanges = Self.colorRanges(of: presentations, length: text.length)
        lastURLFoldUpdate = EditorURLFoldUpdate(
            redetectedRange: change.redetectedRange,
            restyleRanges: restyleRanges,
            recolorRanges: recolorRanges
        )
        resetTypingAttributesAroundHiddenText(layout: layout)

        if storageChanged || !recolorRanges.isEmpty {
            needsDisplay = true
        }
    }

    /// `textStorage` の文字の変更の通知を見張り、変更を `urlIndex` に記録する。
    func observeTextStorageIfNeeded() {
        guard let storage = textStorage, storage !== observedTextStorage else { return }
        removeTextStorageObserver()
        observedTextStorage = storage
        urlIndex.invalidate()
        textStorageObserver = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification,
            object: storage,
            queue: nil
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self,
                      let storage = notification.object as? NSTextStorage,
                      storage.editedMask.contains(.editedCharacters)
                else { return }
                self.urlIndex.record(EditorTextEdit(range: storage.editedRange, changeInLength: storage.changeInLength))
            }
        }
    }

    /// 文字の変更の通知の見張りをやめる。
    func removeTextStorageObserver() {
        if let textStorageObserver {
            NotificationCenter.default.removeObserver(textStorageObserver)
        }
        textStorageObserver = nil
        observedTextStorage = nil
    }

    /// 今の見え方から作った、隠す文字ごとの字間。
    var appliedHiddenKerns: [EditorHiddenKern] {
        guard foldsURLs, let layout = textLayout else { return [] }
        return EditorURLFoldStyler(font: layout.font, baseKern: layout.kern)
            .hiddenKerns(for: urlPresentations, in: string as NSString)
    }

    /// 変換の前に畳んだ URL があるとき、文書の先頭から変換のある段落の終わりまでの配置を確定させる。
    func ensureLayoutBeforeMarkedText() {
        guard foldsURLs, hasMarkedText() else { return }
        let marked = markedRange()
        guard EditorURLFoldStyler.needsLayoutBeforeMarkedText(presentations: urlPresentations, markedLocation: marked.location) else { return }
        ensureLayout(throughParagraphOf: marked)
    }

    /// 変換中でなければ、文書の先頭からカーソルのある段落の終わりまでの配置を確定させる。
    func ensureLayoutBeforeCaret() {
        guard !hasMarkedText() else { return }
        ensureLayout(throughParagraphOf: selectedRange())
    }

    private func ensureLayout(throughParagraphOf range: NSRange) {
        guard let layoutManager = textLayoutManager,
              let contentManager = layoutManager.textContentManager
        else { return }
        let text = string as NSString
        guard range.location <= text.length else { return }
        let end = NSMaxRange(text.paragraphRange(for: range))
        guard let textRange = Self.textRange(NSRange(location: 0, length: end), in: contentManager) else { return }
        layoutManager.ensureLayout(for: textRange)
    }

    // MARK: - 「…」

    /// 畳んだ URL の「…」を描く矩形(入力欄の座標)。枠が取れない位置は含まない。
    func urlEllipsisRects() -> [CGRect] {
        guard let font = textLayout?.font,
              let storage = textStorage,
              let layoutManager = textLayoutManager,
              let contentManager = layoutManager.textContentManager
        else { return [] }
        var locations: [Int] = []
        storage.enumerateAttribute(.editorURLEllipsis, in: NSRange(location: 0, length: storage.length), options: []) { value, range, _ in
            guard value != nil else { return }
            locations.append(contentsOf: range.location..<NSMaxRange(range))
        }
        let size = urlEllipsisString(font: font).size()
        let origin = textContainerOrigin
        var rects: [CGRect] = []
        for location in locations {
            guard let range = Self.textRange(NSRange(location: location, length: 1), in: contentManager) else { continue }
            layoutManager.enumerateTextSegments(in: range, type: .standard, options: []) { _, frame, baseline, _ in
                let x = frame.minX + origin.x
                let y = frame.minY + origin.y + baseline - font.ascender
                if x.isFinite, y.isFinite {
                    rects.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
                }
                return false
            }
        }
        return rects
    }

    /// 畳んだ URL の「…」を描く。
    func drawURLEllipses(in dirtyRect: NSRect) {
        guard let font = textLayout?.font, hasURLFoldMarks else { return }
        let string = urlEllipsisString(font: font)
        for rect in urlEllipsisRects() where rect.intersects(dirtyRect) {
            string.draw(at: rect.origin)
        }
    }

    // MARK: - リンクのアイコン

    /// 畳んだ URL の先頭のリンクのアイコンを描く矩形(入力欄の座標)。枠が取れない位置は含まない。
    func urlLinkIconRects() -> [CGRect] {
        guard let font = textLayout?.font,
              let size = EditorURLLinkIcon.size(pointSize: font.pointSize),
              let storage = textStorage,
              let layoutManager = textLayoutManager,
              let contentManager = layoutManager.textContentManager
        else { return [] }
        var locations: [Int] = []
        storage.enumerateAttribute(.editorURLLinkIcon, in: NSRange(location: 0, length: storage.length), options: []) { value, range, _ in
            guard value != nil else { return }
            locations.append(contentsOf: range.location..<NSMaxRange(range))
        }
        let origin = textContainerOrigin
        var rects: [CGRect] = []
        for location in locations {
            guard let range = Self.textRange(NSRange(location: location, length: 1), in: contentManager) else { continue }
            layoutManager.enumerateTextSegments(in: range, type: .standard, options: []) { _, frame, baseline, _ in
                let rect = EditorURLLinkIcon.rect(
                    minX: frame.minX + origin.x,
                    baselineY: frame.minY + origin.y + baseline,
                    ascender: font.ascender,
                    descender: font.descender,
                    size: size
                )
                if rect.origin.x.isFinite, rect.origin.y.isFinite {
                    rects.append(rect)
                }
                return false
            }
        }
        return rects
    }

    /// 畳んだ URL の先頭のリンクのアイコンを描く。
    func drawURLLinkIcons(in dirtyRect: NSRect) {
        guard let font = textLayout?.font, hasURLFoldMarks,
              let image = EditorURLLinkIcon.image(pointSize: font.pointSize, color: EditorURLFoldStyler.urlColor)
        else { return }
        for rect in urlLinkIconRects() where rect.intersects(dirtyRect) {
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    private func urlEllipsisString(font: NSFont) -> NSAttributedString {
        NSAttributedString(
            string: EditorURLFold.ellipsis,
            attributes: [.font: font, .foregroundColor: EditorURLFoldStyler.urlColor]
        )
    }

    // MARK: - 付け直しの部品

    private func clearURLFolds() {
        urlPresentations = []
        var changed = false
        if hasURLFoldMarks, let storage = textStorage {
            let styler = EditorURLFoldStyler(font: textLayout?.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize), baseKern: textLayout?.kern ?? 0)
            changed = styler.apply([], to: storage)
        }
        if !appliedURLColorRanges.isEmpty, let layoutManager = textLayoutManager {
            layoutManager.removeRenderingAttribute(.foregroundColor, for: layoutManager.documentRange)
            changed = true
        }
        hasURLFoldMarks = false
        appliedURLColorRanges = []
        if changed {
            if let layoutManager = textLayoutManager {
                layoutManager.ensureLayout(for: layoutManager.documentRange)
            }
            refreshCaret()
            needsDisplay = true
        }
    }

    private func keepCaretLineInPlace(selection: NSRange, minYBefore: CGFloat?) {
        guard let minYBefore,
              selection.location != NSNotFound,
              let scrollView = enclosingScrollView
        else { return }
        sizeToFit()
        guard let minYAfter = caretSegmentRect(at: selection.location)?.minY else { return }
        let clip = scrollView.contentView
        let originY = EditorURLScrollAnchor.adjustedOriginY(
            caretMinYBefore: minYBefore,
            caretMinYAfter: minYAfter,
            currentOriginY: clip.bounds.origin.y,
            documentHeight: frame.height,
            visibleHeight: clip.bounds.height
        )
        guard originY != clip.bounds.origin.y else { return }
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: originY))
        scrollView.reflectScrolledClipView(clip)
    }

    private func applyURLColors(
        _ presentations: [EditorURLPresentation],
        in ranges: [NSRange],
        length: Int,
        layoutManager: NSTextLayoutManager,
        contentManager: NSTextContentManager
    ) {
        for scope in ranges {
            if let scopeRange = Self.textRange(scope, in: contentManager) {
                layoutManager.removeRenderingAttribute(.foregroundColor, for: scopeRange)
            }
            for presentation in presentations where NSIntersectionRange(presentation.url.range, scope).length > 0 {
                let urlRange = LineEditing.clamped(presentation.url.range, toLength: length)
                if let range = Self.textRange(urlRange, in: contentManager) {
                    layoutManager.addRenderingAttribute(.foregroundColor, value: EditorURLFoldStyler.urlColor, for: range)
                }
                for hidden in Self.hiddenRanges(of: presentation, length: length) {
                    if let range = Self.textRange(hidden, in: contentManager) {
                        layoutManager.addRenderingAttribute(.foregroundColor, value: NSColor.clear, for: range)
                    }
                }
            }
        }
        if !findHighlights.isEmpty {
            FindHighlighter.apply(findHighlights, to: self)
        }
    }

    private func resetTypingAttributesAroundHiddenText(layout: EditorTextLayout) {
        var attributes = typingAttributes
        var changed = false
        for key in [NSAttributedString.Key.editorURLHidden, .editorURLEllipsis, .editorURLLinkIcon, .ligature] where attributes[key] != nil {
            attributes[key] = nil
            changed = true
        }
        let currentKern = (attributes[.kern] as? NSNumber)?.doubleValue
        if layout.kern > 0 {
            if currentKern != Double(layout.kern) {
                attributes[.kern] = layout.kern
                changed = true
            }
        } else if currentKern != nil {
            attributes[.kern] = nil
            changed = true
        }
        if changed {
            typingAttributes = attributes
        }
    }

    private static func hiddenRanges(of presentation: EditorURLPresentation, length: Int) -> [NSRange] {
        guard let fold = presentation.fold else { return [] }
        var ranges = [fold.schemeRange]
        if let middle = fold.middleRange {
            ranges.append(middle)
        }
        return ranges.map { LineEditing.clamped($0, toLength: length) }
    }

    private static func colorRanges(of presentations: [EditorURLPresentation], length: Int) -> [NSRange] {
        presentations.flatMap { presentation in
            [LineEditing.clamped(presentation.url.range, toLength: length)]
                + hiddenRanges(of: presentation, length: length)
        }
    }

    private static func textRange(_ range: NSRange, in contentManager: NSTextContentManager) -> NSTextRange? {
        let start = contentManager.documentRange.location
        guard let lower = contentManager.location(start, offsetBy: range.location),
              let upper = contentManager.location(lower, offsetBy: range.length)
        else { return nil }
        return NSTextRange(location: lower, end: upper)
    }
}
