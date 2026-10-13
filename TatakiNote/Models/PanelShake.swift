import CoreGraphics
import Foundation

/// パネルを横に揺らす動きの値。
enum PanelShake {
    /// 元の位置からの横のずれ(pt)を順に並べたもの。最後は 0。
    static let offsets: [CGFloat] = [-9, 8, -6, 4, -2, 0]
    /// 1 歩の時間。`offsets.count` 歩で 420ms。
    static let stepDuration: Duration = .milliseconds(70)

    private static let tolerance: CGFloat = 0.5

    /// 次の 1 歩を進めてよいか。今の位置が前の歩で置いた位置と違えば、誰かが動かしたので止める。
    static func shouldContinue(currentOrigin: CGPoint, lastPlacedOrigin: CGPoint) -> Bool {
        abs(currentOrigin.x - lastPlacedOrigin.x) <= tolerance && abs(currentOrigin.y - lastPlacedOrigin.y) <= tolerance
    }

    /// 揺らし始めてよいか。開く・閉じる動きの途中は揺らさない。
    static func canStart(motionPhase: PanelMotionPhase) -> Bool {
        motionPhase == .shown
    }
}
