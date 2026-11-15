import AppKit

/// 今いる行のハイライトの範囲・矩形・色。
enum EditorCurrentLine {
    /// 控えめな背景の色(ライト: 黒 5%、ダーク: 白 7%)。
    static let color = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.07)
            : NSColor.black.withAlphaComponent(0.05)
    }

    /// ハイライトする段落の範囲。オフ・選択が長さ 1 以上なら nil。
    static func paragraphRange(in text: NSString, selection: NSRange, isEnabled: Bool) -> NSRange? {
        guard isEnabled, selection.length == 0, selection.location != NSNotFound,
              selection.location >= 0, selection.location <= text.length
        else { return nil }
        return text.paragraphRange(for: NSRange(location: selection.location, length: 0))
    }

    /// 段落の行の矩形から、ハイライトの矩形(左右はテキストコンテナの幅)。行が無ければ caretRect の行。
    static func rect(lineRects: [CGRect], caretRect: CGRect?, containerMinX: CGFloat, containerWidth: CGFloat) -> CGRect? {
        guard containerWidth > 0, containerMinX.isFinite, containerWidth.isFinite else { return nil }
        let lines = lineRects.filter { $0.origin.y.isFinite && $0.height.isFinite && $0.height > 0 }
        let minY: CGFloat
        let maxY: CGFloat
        if let top = lines.map(\.minY).min(), let bottom = lines.map(\.maxY).max() {
            minY = top
            maxY = bottom
        } else if let caretRect, caretRect.origin.y.isFinite, caretRect.height.isFinite, caretRect.height > 0 {
            minY = caretRect.minY
            maxY = caretRect.maxY
        } else {
            return nil
        }
        return CGRect(x: containerMinX, y: minY, width: containerWidth, height: maxY - minY)
    }
}
