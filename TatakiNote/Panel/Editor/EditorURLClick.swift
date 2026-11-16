import AppKit

/// クリックで URL を開くかの判定。
enum EditorURLClick {
    /// 修飾キーが ⌘ だけ(capsLock・function・numericPad は無視)なら true。
    static func opensURL(modifiers: NSEvent.ModifierFlags) -> Bool {
        var flags = modifiers.intersection(.deviceIndependentFlagsMask)
        flags.subtract([.capsLock, .function, .numericPad])
        return flags == .command
    }

    /// 点を含む矩形を持つ URL。無ければ nil。
    static func url(at point: CGPoint, in areas: [EditorURLHitArea]) -> EditorURL? {
        areas.first { area in area.rects.contains { $0.contains(point) } }?.url
    }
}

/// URL と、入力欄の座標でのその矩形。
struct EditorURLHitArea: Equatable {
    let url: EditorURL
    let rects: [CGRect]
    let isFolded: Bool
}

/// 入力欄の吹き出しの文字を、点から求めて返す持ち主。
final class EditorURLToolTipOwner: NSObject, NSViewToolTipOwner {
    private let provider: (CGPoint) -> String?

    init(provider: @escaping (CGPoint) -> String?) {
        self.provider = provider
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        provider(point) ?? ""
    }
}
