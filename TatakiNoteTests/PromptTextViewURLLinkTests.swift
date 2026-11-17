import AppKit
import Testing
@testable import TatakiNote

@MainActor
private final class RecordingURLOpener: EditorURLOpening {
    private(set) var opened: [URL] = []

    func open(_ url: URL) {
        opened.append(url)
    }
}

@MainActor
private final class CursorRecorder {
    var cursors: [NSCursor] = []
}

@MainActor
private final class LinkFixture {
    static let longURL = "https://example.com/docs/2026/11/some-page"
    static let shortURL = "https://example.com/s"
    static let outsidePoint = CGPoint(x: 380, y: 280)

    let textView = PromptTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    let opener = RecordingURLOpener()

    init(text: String, selection: NSRange = NSRange(location: 0, length: 0), foldsURLs: Bool = true) {
        textView.isRichText = false
        textView.applyFont(NSFont.systemFont(ofSize: 14))
        textView.applyReadability(.standard)
        textView.urlOpener = opener
        textView.foldsURLs = foldsURLs
        textView.string = text
        textView.setSelectedRange(selection)
        if let layoutManager = textView.textLayoutManager {
            layoutManager.ensureLayout(for: layoutManager.documentRange)
        }
        textView.refreshURLFolds(textDidChange: true)
    }

    var firstArea: EditorURLHitArea? {
        textView.urlHitAreas.first
    }

    var centerOfFirstURL: CGPoint {
        let rect = firstArea?.rects.first ?? .zero
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    func hasRenderedColor(in range: NSRange) -> Bool {
        guard let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager
        else { return false }
        var found = false
        for location in range.location..<NSMaxRange(range) {
            guard let start = contentManager.location(contentManager.documentRange.location, offsetBy: location) else { continue }
            layoutManager.enumerateRenderingAttributes(from: start, reverse: false) { _, attributes, renderedRange in
                if renderedRange.contains(start), attributes[.foregroundColor] != nil {
                    found = true
                }
                return false
            }
        }
        return found
    }

    func hasNegativeKernOrHiddenMark() -> Bool {
        guard let storage = textView.textStorage else { return false }
        var found = false
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length), options: []) { attributes, _, _ in
            if let kern = (attributes[.kern] as? NSNumber)?.doubleValue, kern < 0 {
                found = true
            }
            if attributes[.editorURLHidden] != nil {
                found = true
            }
        }
        return found
    }
}

@MainActor
struct PromptTextViewURLLinkTests {
    private let foldedText = "memo " + LinkFixture.longURL + " end"

    // MARK: - 吹き出し

    @Test("AC-17: 畳んだ URL の矩形の上では吹き出しの文字が URL の全文になる")
    func toolTipOnFoldedURL() throws {
        let fixture = LinkFixture(text: foldedText)
        let area = try #require(fixture.firstArea)
        #expect(area.isFolded)
        #expect(!area.rects.isEmpty)
        #expect(fixture.textView.urlToolTip(at: fixture.centerOfFirstURL) == LinkFixture.longURL)
        #expect(fixture.textView.urlToolTipTags.count == area.rects.count)
    }

    @Test("AC-17: 畳んでいない URL・URL の外では吹き出しが出ない")
    func noToolTipOnUnfoldedOrOutside() throws {
        let short = LinkFixture(text: "memo " + LinkFixture.shortURL + " end")
        #expect(short.firstArea?.isFolded == false)
        #expect(short.textView.urlToolTip(at: short.centerOfFirstURL) == nil)
        #expect(short.textView.urlToolTipTags.isEmpty)

        let revealed = LinkFixture(text: foldedText, selection: NSRange(location: 6, length: 0))
        #expect(revealed.firstArea?.isFolded == false)
        #expect(revealed.textView.urlToolTip(at: revealed.centerOfFirstURL) == nil)
        #expect(revealed.textView.urlToolTipTags.isEmpty)

        let folded = LinkFixture(text: foldedText)
        #expect(folded.textView.urlToolTip(at: LinkFixture.outsidePoint) == nil)
    }

    @Test("AC-17: 設定オフでは吹き出しが付かず、矩形だけが作られる")
    func noToolTipWhenOff() {
        let fixture = LinkFixture(text: foldedText, foldsURLs: false)
        #expect(fixture.firstArea?.isFolded == false)
        #expect(fixture.firstArea?.rects.isEmpty == false)
        #expect(fixture.textView.urlToolTipTags.isEmpty)
        #expect(fixture.textView.urlToolTip(at: fixture.centerOfFirstURL) == nil)
    }

    @Test("AC-17: 設定をオフにすると付けた吹き出しが外れ、矩形は残る")
    func toolTipsRemovedWhenTurnedOff() {
        let fixture = LinkFixture(text: foldedText)
        #expect(!fixture.textView.urlToolTipTags.isEmpty)
        fixture.textView.foldsURLs = false
        #expect(fixture.textView.urlToolTipTags.isEmpty)
        #expect(fixture.firstArea?.isFolded == false)
        #expect(fixture.firstArea?.rects.isEmpty == false)
    }

    // MARK: - ⌘ クリック

    @Test("AC-18: 畳んだ URL を ⌘ クリックすると全文を開く役に渡し、選択は変わらない")
    func commandClickOpensFoldedURL() throws {
        let fixture = LinkFixture(text: foldedText)
        let selection = fixture.textView.selectedRange()
        let handled = fixture.textView.handleURLClick(at: fixture.centerOfFirstURL, modifiers: .command)
        #expect(handled)
        #expect(fixture.opener.opened == [try #require(URL(string: LinkFixture.longURL))])
        #expect(fixture.textView.selectedRange() == selection)
    }

    @Test("AC-18: 開いている URL を ⌘ クリックしても全文を開き、選択は変わらない")
    func commandClickOpensRevealedURL() throws {
        let fixture = LinkFixture(text: foldedText, selection: NSRange(location: 6, length: 0))
        #expect(fixture.firstArea?.isFolded == false)
        let handled = fixture.textView.handleURLClick(at: fixture.centerOfFirstURL, modifiers: .command)
        #expect(handled)
        #expect(fixture.opener.opened == [try #require(URL(string: LinkFixture.longURL))])
        #expect(fixture.textView.selectedRange() == NSRange(location: 6, length: 0))
    }

    @Test("AC-18: 修飾キーなし・⌘ 以外の組み合わせ・URL の外では開かない")
    func otherClicksDoNotOpen() {
        let fixture = LinkFixture(text: foldedText)
        let center = fixture.centerOfFirstURL
        #expect(!fixture.textView.handleURLClick(at: center, modifiers: []))
        #expect(!fixture.textView.handleURLClick(at: center, modifiers: .shift))
        #expect(!fixture.textView.handleURLClick(at: center, modifiers: [.command, .shift]))
        #expect(!fixture.textView.handleURLClick(at: center, modifiers: [.command, .option]))
        #expect(!fixture.textView.handleURLClick(at: LinkFixture.outsidePoint, modifiers: .command))
        #expect(fixture.opener.opened.isEmpty)
    }

    @Test("AC-18: 設定オフでも ⌘ クリックで URL の全文を開く役に渡し、色と字間は付かない")
    func commandClickOpensWhenOff() throws {
        let fixture = LinkFixture(text: foldedText, foldsURLs: false)
        let handled = fixture.textView.handleURLClick(at: fixture.centerOfFirstURL, modifiers: .command)
        #expect(handled)
        #expect(fixture.opener.opened == [try #require(URL(string: LinkFixture.longURL))])
        #expect(fixture.textView.appliedHiddenKerns.isEmpty)
        #expect(fixture.textView.appliedURLColorRanges.isEmpty)
        #expect(!fixture.textView.handleURLClick(at: fixture.centerOfFirstURL, modifiers: []))
        #expect(!fixture.textView.handleURLClick(at: LinkFixture.outsidePoint, modifiers: .command))
        #expect(fixture.opener.opened.count == 1)
    }

    @Test("AC-18: 設定オフでは URL に色の rendering 属性も負の字間も付かない(最初からオフ・オンからオフ)")
    func noStyleWhenOff() {
        let urlRange = (foldedText as NSString).range(of: LinkFixture.longURL)
        let fromStart = LinkFixture(text: foldedText, foldsURLs: false)
        #expect(!fromStart.hasRenderedColor(in: urlRange))
        #expect(!fromStart.hasNegativeKernOrHiddenMark())
        #expect(fromStart.textView.urlEllipsisRects().isEmpty)
        #expect(fromStart.textView.urlLinkIconRects().isEmpty)

        let switched = LinkFixture(text: foldedText)
        #expect(switched.hasNegativeKernOrHiddenMark())
        #expect(!switched.textView.urlLinkIconRects().isEmpty)
        switched.textView.foldsURLs = false
        #expect(!switched.hasRenderedColor(in: urlRange))
        #expect(!switched.hasNegativeKernOrHiddenMark())
        #expect(switched.textView.urlLinkIconRects().isEmpty)
        #expect(switched.textView.appliedHiddenKerns.isEmpty)
        #expect(switched.textView.appliedURLColorRanges.isEmpty)
    }

    @Test("AC-18: オンからオフにしても ⌘ クリックで URL の全文を開く")
    func commandClickOpensAfterTurningOff() throws {
        let fixture = LinkFixture(text: foldedText)
        fixture.textView.foldsURLs = false
        #expect(fixture.textView.handleURLClick(at: fixture.centerOfFirstURL, modifiers: .command))
        #expect(fixture.opener.opened == [try #require(URL(string: LinkFixture.longURL))])
    }

    // MARK: - 右クリックのメニュー

    @Test("AC-19: URL の上のメニューは先頭に「リンクを開く」があり、元の項目も残る")
    func menuHasOpenLinkFirst() throws {
        let fixture = LinkFixture(text: foldedText)
        let url = try #require(fixture.firstArea?.url)
        let base = NSMenu()
        base.addItem(NSMenuItem(title: "コピー", action: nil, keyEquivalent: ""))
        base.addItem(NSMenuItem(title: "ペースト", action: nil, keyEquivalent: ""))

        let menu = fixture.textView.urlContextMenu(base: base, url: url)
        let first = try #require(menu.items.first)
        #expect(first.title == "リンクを開く")
        #expect(first.identifier?.rawValue == "promptPanel.openLink")
        #expect(first.representedObject as? String == LinkFixture.longURL)
        #expect(first.target === fixture.textView)
        #expect(menu.items[1].isSeparatorItem)
        #expect(menu.items.map(\.title).contains("コピー"))
        #expect(menu.items.map(\.title).contains("ペースト"))
    }

    @Test("AC-19: 元のメニューが無くても「リンクを開く」だけのメニューを返す")
    func menuWithoutBase() throws {
        let fixture = LinkFixture(text: foldedText)
        let url = try #require(fixture.firstArea?.url)
        let menu = fixture.textView.urlContextMenu(base: nil, url: url)
        #expect(menu.items.count == 1)
        #expect(menu.items.first?.title == "リンクを開く")
    }

    @Test("AC-19: 「リンクを開く」を選ぶとその URL を開く役に渡す")
    func openLinkItemOpensURL() throws {
        let fixture = LinkFixture(text: foldedText)
        let url = try #require(fixture.firstArea?.url)
        let menu = fixture.textView.urlContextMenu(base: NSMenu(), url: url)
        let item = try #require(menu.items.first)
        let target = try #require(item.target as? NSObject)
        let action = try #require(item.action)
        _ = target.perform(action, with: item)
        #expect(fixture.opener.opened == [try #require(URL(string: LinkFixture.longURL))])
    }

    @Test("AC-19: URL の上なら右クリックの対象の URL が決まり、URL の外では決まらない")
    func contextMenuURLLookup() {
        let fixture = LinkFixture(text: foldedText)
        #expect(fixture.textView.urlForContextMenu(at: fixture.centerOfFirstURL)?.text == LinkFixture.longURL)
        #expect(fixture.textView.urlForContextMenu(at: LinkFixture.outsidePoint) == nil)
    }

    @Test("AC-19: 設定オフでも URL の上の右クリックの対象が決まり、メニューに「リンクを開く」がある")
    func contextMenuWhenOff() throws {
        let off = LinkFixture(text: foldedText, foldsURLs: false)
        let url = try #require(off.textView.urlForContextMenu(at: off.centerOfFirstURL))
        #expect(url.text == LinkFixture.longURL)
        #expect(off.textView.urlForContextMenu(at: LinkFixture.outsidePoint) == nil)
        let menu = off.textView.urlContextMenu(base: NSMenu(), url: url)
        let item = try #require(menu.items.first)
        #expect(item.title == "リンクを開く")
        let target = try #require(item.target as? NSObject)
        let action = try #require(item.action)
        _ = target.perform(action, with: item)
        #expect(off.opener.opened == [try #require(URL(string: LinkFixture.longURL))])
    }

    // MARK: - マウスカーソル

    private func cursorFixture(text: String, selection: NSRange = NSRange(location: 0, length: 0), foldsURLs: Bool = true) -> (LinkFixture, CursorRecorder) {
        let fixture = LinkFixture(text: text, selection: selection, foldsURLs: foldsURLs)
        let recorder = CursorRecorder()
        fixture.textView.urlCursorApplier = { recorder.cursors.append($0) }
        return (fixture, recorder)
    }

    private let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)

    @Test("AC-28: ⌘ だけで URL の上なら指にし、外れる・⌘ を離す・他の修飾キーが加わると I ビームに戻す")
    func pointingHandFollowsConditions() {
        let (fixture, recorder) = cursorFixture(text: foldedText)
        let textView = fixture.textView
        let inside = fixture.centerOfFirstURL

        textView.updateURLCursor(at: inside, modifiers: .command, visibleRect: bounds)
        #expect(recorder.cursors == [.pointingHand])
        #expect(textView.isShowingURLPointingHand)

        textView.updateURLCursor(at: LinkFixture.outsidePoint, modifiers: .command, visibleRect: bounds)
        #expect(recorder.cursors == [.pointingHand, .iBeam])
        #expect(!textView.isShowingURLPointingHand)

        textView.updateURLCursor(at: inside, modifiers: .command, visibleRect: bounds)
        textView.updateURLCursor(at: inside, modifiers: [], visibleRect: bounds)
        #expect(recorder.cursors.suffix(2) == [.pointingHand, .iBeam])

        textView.updateURLCursor(at: inside, modifiers: .command, visibleRect: bounds)
        textView.updateURLCursor(at: inside, modifiers: [.command, .shift], visibleRect: bounds)
        #expect(recorder.cursors.suffix(2) == [.pointingHand, .iBeam])
        #expect(!textView.isShowingURLPointingHand)
    }

    @Test("AC-28: 指にしていない間は何も設定しない")
    func noCursorWhenNotShowingHand() {
        let (fixture, recorder) = cursorFixture(text: foldedText)
        let inside = fixture.centerOfFirstURL
        fixture.textView.updateURLCursor(at: inside, modifiers: [], visibleRect: bounds)
        fixture.textView.updateURLCursor(at: LinkFixture.outsidePoint, modifiers: .command, visibleRect: bounds)
        fixture.textView.updateURLCursor(at: inside, modifiers: .shift, visibleRect: bounds)
        #expect(recorder.cursors.isEmpty)
    }

    @Test("AC-28: 指にしている間は動くたびに指を設定し直す")
    func reappliesHandWhileOverURL() {
        let (fixture, recorder) = cursorFixture(text: foldedText)
        let inside = fixture.centerOfFirstURL
        fixture.textView.updateURLCursor(at: inside, modifiers: .command, visibleRect: bounds)
        fixture.textView.updateURLCursor(at: inside, modifiers: .command, visibleRect: bounds)
        #expect(recorder.cursors == [.pointingHand, .pointingHand])
    }

    @Test("AC-28: 開いた URL・30 文字以下の URL・設定オフのどれでも指にする")
    func pointingHandForEveryPresentation() {
        let revealed = cursorFixture(text: foldedText, selection: NSRange(location: 6, length: 0))
        #expect(revealed.0.firstArea?.isFolded == false)
        revealed.0.textView.updateURLCursor(at: revealed.0.centerOfFirstURL, modifiers: .command, visibleRect: bounds)
        #expect(revealed.1.cursors == [.pointingHand])

        let short = cursorFixture(text: "memo " + LinkFixture.shortURL + " end")
        short.0.textView.updateURLCursor(at: short.0.centerOfFirstURL, modifiers: .command, visibleRect: bounds)
        #expect(short.1.cursors == [.pointingHand])

        let off = cursorFixture(text: foldedText, foldsURLs: false)
        off.0.textView.updateURLCursor(at: off.0.centerOfFirstURL, modifiers: .command, visibleRect: bounds)
        #expect(off.1.cursors == [.pointingHand])
    }

    // MARK: - パネルの吹き出しの設定

    @Test("AC-25: パネルは TatakiNote がアクティブでない間も吹き出しを出す設定になっている")
    func panelAllowsToolTipsWhenInactive() {
        let panel = PromptPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300))
        #expect(panel.allowsToolTipsWhenApplicationIsInactive)
    }
}
