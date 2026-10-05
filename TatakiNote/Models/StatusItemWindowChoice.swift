import CoreGraphics

/// 吹き出しの出どころにするメニューバーの窓の選び方。
enum StatusItemWindowChoice {
    /// マウスのある画面の窓を優先して選ぶ。無ければ最初の窓。窓が無ければ `nil`。
    static func index(windowFrames: [CGRect], screenFrames: [CGRect], mouseLocation: CGPoint) -> Int? {
        guard !windowFrames.isEmpty else { return nil }
        if let screenFrame = screenFrames.first(where: { $0.contains(mouseLocation) }),
           let index = windowFrames.firstIndex(where: { screenFrame.contains(CGPoint(x: $0.midX, y: $0.midY)) }) {
            return index
        }
        return 0
    }
}
