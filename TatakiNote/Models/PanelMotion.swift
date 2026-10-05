import CoreGraphics
import Foundation

/// パネルの開閉の動きの決まり。
enum PanelMotion {
    /// 開く・閉じるそれぞれの動きの長さ(秒)。
    static let duration: TimeInterval = 0.2
    /// 線になったときの高さ。
    static let lineHeight: CGFloat = 2

    /// `frame` の縦の中心にある、同じ幅・x の横線の枠。
    static func lineFrame(of frame: CGRect) -> CGRect {
        CGRect(x: frame.minX, y: frame.midY - lineHeight / 2, width: frame.width, height: lineHeight)
    }
}

/// パネルの開閉の動きの進み具合。
enum PanelMotionPhase: Equatable {
    case hidden
    case opening
    case shown
    case closing
}

/// パネルの開閉の動きの状態。古い動きの終わりの知らせを見分ける。
struct PanelMotionState: Equatable {
    private(set) var phase: PanelMotionPhase = .hidden
    private(set) var generation = 0

    /// 開く動きを始める。返した番号を、動きの終わりに `finish(_:)` へ渡す。
    mutating func beginOpening() -> Int {
        generation += 1
        phase = .opening
        return generation
    }

    /// 閉じる動きを始める。
    mutating func beginClosing() -> Int {
        generation += 1
        phase = .closing
        return generation
    }

    /// 動きなしで開いた状態にする。
    mutating func showWithoutMotion() {
        generation += 1
        phase = .shown
    }

    /// 動きなしで閉じた状態にする。
    mutating func hideWithoutMotion() {
        generation += 1
        phase = .hidden
    }

    /// 動きが終わったとき。番号が今の動きのものなら次の状態へ進めて true。古い番号なら何も変えず false。
    mutating func finish(_ token: Int) -> Bool {
        guard token == generation else { return false }
        switch phase {
        case .opening:
            phase = .shown
            return true
        case .closing:
            phase = .hidden
            return true
        case .hidden, .shown:
            return false
        }
    }
}
