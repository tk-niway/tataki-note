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

    @Test("AC-17: 設定オフでは吹き出しも矩形も付かない")
    func noToolTipWhenOff() {
        let fixture = LinkFixture(text: foldedText, foldsURLs: false)
        #expect(fixture.textView.urlHitAreas.isEmpty)
        #expect(fixture.textView.urlToolTipTags.isEmpty)
        #expect(fixture.textView.urlToolTip(at: CGPoint(x: 40, y: 10)) == nil)
    }

    @Test("AC-17: 設定をオフにすると付けた吹き出しが外れる")
    func toolTipsRemovedWhenTurnedOff() {
        let fixture = LinkFixture(text: foldedText)
        #expect(!fixture.textView.urlToolTipTags.isEmpty)
        fixture.textView.foldsURLs = false
        #expect(fixture.textView.urlToolTipTags.isEmpty)
        #expect(fixture.textView.urlHitAreas.isEmpty)
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

    @Test("AC-18: 設定オフでは ⌘ クリックで開かない")
    func commandClickDoesNothingWhenOff() {
        let fixture = LinkFixture(text: foldedText, foldsURLs: false)
        #expect(!fixture.textView.handleURLClick(at: CGPoint(x: 40, y: 10), modifiers: .command))
        #expect(fixture.opener.opened.isEmpty)
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

    @Test("AC-19: URL の上なら右クリックの対象の URL が決まり、URL の外・設定オフでは決まらない")
    func contextMenuURLLookup() {
        let fixture = LinkFixture(text: foldedText)
        #expect(fixture.textView.urlForContextMenu(at: fixture.centerOfFirstURL)?.text == LinkFixture.longURL)
        #expect(fixture.textView.urlForContextMenu(at: LinkFixture.outsidePoint) == nil)

        let off = LinkFixture(text: foldedText, foldsURLs: false)
        #expect(off.textView.urlForContextMenu(at: CGPoint(x: 40, y: 10)) == nil)
    }

    // MARK: - パネルの吹き出しの設定

    @Test("AC-25: パネルは TatakiNote がアクティブでない間も吹き出しを出す設定になっている")
    func panelAllowsToolTipsWhenInactive() {
        let panel = PromptPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300))
        #expect(panel.allowsToolTipsWhenApplicationIsInactive)
    }
}
