import CoreGraphics
import Foundation

/// 挿入・送信の後に出すトーストの文と置き場所。
enum InsertionToast {
    /// トーストを出している時間。
    static let duration: Duration = .milliseconds(1900)

    /// 「<アプリ名> に挿入しました」「<アプリ名> に送信しました」。名前が無い・空白だけなら「挿入しました」「送信しました」。
    static func message(appName: String?, didSend: Bool) -> String {
        let action = didSend ? "送信しました" : "挿入しました"
        guard let name = appName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return action
        }
        return "\(name) に\(action)"
    }

    /// トーストの窓の枠。パネルがあった枠の中央に置き、画面の見える範囲からはみ出すなら内側へ寄せる。
    static func frame(toastSize: CGSize, panelFrame: CGRect, visibleFrame: CGRect?) -> CGRect {
        var origin = CGPoint(
            x: panelFrame.midX - toastSize.width / 2,
            y: panelFrame.midY - toastSize.height / 2
        )
        if let visibleFrame {
            origin.x = clamped(origin.x, length: toastSize.width, lower: visibleFrame.minX, upper: visibleFrame.maxX)
            origin.y = clamped(origin.y, length: toastSize.height, lower: visibleFrame.minY, upper: visibleFrame.maxY)
        }
        return CGRect(origin: origin, size: toastSize)
    }

    private static func clamped(_ value: CGFloat, length: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        if length >= upper - lower {
            return lower
        }
        return min(max(value, lower), upper - length)
    }
}
