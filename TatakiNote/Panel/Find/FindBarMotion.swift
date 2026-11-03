import SwiftUI

/// 検索バーの出入りの動き。
enum FindBarMotion {
    static let duration: Double = 0.18

    /// 検索バーの開閉・置換の行の開閉に使う動き。動きを止めているなら nil(動きなし)。
    static func animation(isReduced: Bool) -> Animation? {
        isReduced ? nil : .easeOut(duration: duration)
    }

    /// 検索バー・置換の行が出入りするときの見え方。上から出て上へ消える。
    static func transition(isReduced: Bool) -> AnyTransition {
        isReduced ? .identity : .move(edge: .top).combined(with: .opacity)
    }
}

/// 検索バーと置換の行の出入りに、設定のアニメーションに従った動きを付ける。
struct FindBarMotionModifier: ViewModifier {
    let isBarVisible: Bool
    let isReplaceShown: Bool

    @Environment(\.isAppAnimationReduced) private var isReduced

    func body(content: Content) -> some View {
        content
            .animation(FindBarMotion.animation(isReduced: isReduced), value: isBarVisible)
            .animation(FindBarMotion.animation(isReduced: isReduced), value: isReplaceShown)
    }
}
