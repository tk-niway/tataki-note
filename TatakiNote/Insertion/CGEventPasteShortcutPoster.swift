import CoreGraphics

protocol PasteShortcutPosting {
    func postPasteShortcut()
}

struct CGEventPasteShortcutPoster: PasteShortcutPosting {
    private let vKeyCode: CGKeyCode = 9

    func postPasteShortcut() {
        KeyEventPair(keyCode: vKeyCode, flags: .maskCommand)?.post()
    }
}
