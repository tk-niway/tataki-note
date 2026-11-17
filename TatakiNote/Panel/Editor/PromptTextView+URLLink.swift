import AppKit

extension PromptTextView {
    // MARK: - 当たりと吹き出し

    /// 見え方の全 URL の矩形を作り直し、畳んだ URL に吹き出しを付け直す。
    func refreshURLHitAreas() {
        for tag in urlToolTipTags {
            removeToolTip(tag)
        }
        urlToolTipTags = []
        let length = (string as NSString).length
        urlHitAreas = urlPresentations.map { presentation in
            EditorURLHitArea(
                url: presentation.url,
                rects: FindHighlighter.rects(for: LineEditing.clamped(presentation.url.range, toLength: length), in: self),
                isFolded: presentation.fold != nil
            )
        }
        for area in urlHitAreas where area.isFolded {
            for rect in area.rects {
                urlToolTipTags.append(addToolTip(rect, owner: urlToolTipOwner, userData: nil))
            }
        }
    }

    /// 点の下の畳んだ URL の全文。無ければ nil。
    func urlToolTip(at point: CGPoint) -> String? {
        guard foldsURLs else { return nil }
        return EditorURLClick.url(at: point, in: urlHitAreas.filter(\.isFolded))?.text
    }

    /// 点の下の URL。無ければ nil。
    func urlForContextMenu(at point: CGPoint) -> EditorURL? {
        return EditorURLClick.url(at: point, in: urlHitAreas)
    }

    // MARK: - ⌘ クリック

    /// ⌘ クリックで点の下の URL を開く。扱ったら true。
    func handleURLClick(at point: CGPoint, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard EditorURLClick.opensURL(modifiers: modifiers),
              let url = EditorURLClick.url(at: point, in: urlHitAreas)
        else { return false }
        if let target = URL(string: url.text) {
            urlOpener.open(target)
        }
        return true
    }

    // MARK: - マウスカーソル

    /// ⌘ だけを押して URL の上にいるときはカーソルを指にし、外れたら I ビームに戻す。
    func updateURLCursor(at point: CGPoint, modifiers: NSEvent.ModifierFlags, visibleRect: CGRect? = nil) {
        let shows = EditorURLClick.showsPointingHand(
            at: point,
            modifiers: modifiers,
            in: urlHitAreas,
            visibleRect: visibleRect ?? self.visibleRect
        )
        if shows {
            urlCursorApplier(.pointingHand)
            isShowingURLPointingHand = true
        } else if isShowingURLPointingHand {
            urlCursorApplier(.iBeam)
            isShowingURLPointingHand = false
        }
    }

    // MARK: - 右クリックのメニュー

    /// 元のメニューの先頭に「リンクを開く」を足したメニュー。
    func urlContextMenu(base: NSMenu?, url: EditorURL) -> NSMenu {
        let menu = base ?? NSMenu()
        let item = NSMenuItem(
            title: String(localized: "リンクを開く"),
            action: #selector(openLinkFromMenu(_:)),
            keyEquivalent: ""
        )
        item.identifier = NSUserInterfaceItemIdentifier("promptPanel.openLink")
        item.representedObject = url.text
        item.target = self
        if !menu.items.isEmpty {
            menu.insertItem(.separator(), at: 0)
        }
        menu.insertItem(item, at: 0)
        return menu
    }

    /// メニューの「リンクを開く」で、その URL を開く。
    @objc func openLinkFromMenu(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String, let url = URL(string: text) else { return }
        urlOpener.open(url)
    }
}
