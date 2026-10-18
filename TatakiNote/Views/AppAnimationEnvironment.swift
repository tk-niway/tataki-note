import SwiftUI

private struct AppAnimationReducedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// TatakiNote の動きを止めているか。
    var isAppAnimationReduced: Bool {
        get { self[AppAnimationReducedKey.self] }
        set { self[AppAnimationReducedKey.self] = newValue }
    }
}

/// 設定の「アニメーション」と macOS の「視差効果を減らす」から、動きを止めるかを下の View に渡す。
struct AppAnimationModifier: ViewModifier {
    let mode: AnimationMode
    @Environment(\.accessibilityReduceMotion) private var systemReducesMotion

    func body(content: Content) -> some View {
        content.environment(\.isAppAnimationReduced, !mode.isEnabled(reduceMotion: systemReducesMotion))
    }
}

extension View {
    /// 下の View に、動きを止めるかを渡す。
    func appAnimation(mode: AnimationMode) -> some View {
        modifier(AppAnimationModifier(mode: mode))
    }
}
