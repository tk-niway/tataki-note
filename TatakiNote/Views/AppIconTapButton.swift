import AppKit
import SwiftUI

/// 叩くと弾んで言葉が飛ぶ、アプリのアイコン。
struct AppIconTapButton: View {
    @Environment(\.isAppAnimationReduced) private var reduceMotion
    @State private var tapCount = 0
    @State private var flyingWords: [FlyingWord] = []

    private static let iconSize: CGFloat = 80

    var body: some View {
        Button(action: tap) {
            icon
                .frame(width: Self.iconSize, height: Self.iconSize)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .keyframeAnimator(initialValue: IconBounce(), trigger: reduceMotion ? 0 : tapCount) { content, bounce in
                    content
                        .scaleEffect(x: bounce.scaleX, y: 1)
                        .rotationEffect(.degrees(bounce.rotation))
                        .offset(y: bounce.offsetY)
                } keyframes: { _ in
                    KeyframeTrack(\.offsetY) {
                        CubicKeyframe(5, duration: 0.14)
                        CubicKeyframe(-6, duration: 0.18)
                        CubicKeyframe(0, duration: 0.14)
                    }
                    KeyframeTrack(\.scaleX) {
                        CubicKeyframe(0.96, duration: 0.14)
                        CubicKeyframe(1.02, duration: 0.18)
                        CubicKeyframe(1, duration: 0.14)
                    }
                    KeyframeTrack(\.rotation) {
                        CubicKeyframe(-3, duration: 0.14)
                        CubicKeyframe(2, duration: 0.18)
                        CubicKeyframe(0, duration: 0.14)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("TatakiNote")
        .accessibilityIdentifier("settings.appInfo.icon")
        .overlay(alignment: .top) {
            ZStack {
                ForEach(flyingWords) { word in
                    FlyingWordView(word: word) {
                        flyingWords.removeAll { $0.id == word.id }
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let image = NSApp.applicationIconImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "app.dashed")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
    }

    private func tap() {
        guard !reduceMotion else {
            tapCount += 1
            return
        }
        flyingWords.append(FlyingWord(text: AppInfoModel.tapWord(at: tapCount), drift: .random(in: -40...40)))
        tapCount += 1
    }
}

private struct IconBounce {
    var offsetY: CGFloat = 0
    var scaleX: CGFloat = 1
    var rotation: Double = 0
}

private struct FlyingWord: Identifiable {
    let id = UUID()
    let text: String
    let drift: CGFloat
}

private struct FlyingWordState {
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0
    var scale: CGFloat = 1
    var opacity: Double = 1
}

private struct FlyingWordView: View {
    let word: FlyingWord
    let onFinish: () -> Void

    @State private var isFlying = false

    private static let duration: Double = 0.9

    var body: some View {
        Text(verbatim: word.text)
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(Color.accentColor)
            .fixedSize()
            .keyframeAnimator(initialValue: FlyingWordState(), trigger: isFlying) { content, state in
                content
                    .scaleEffect(state.scale)
                    .opacity(state.opacity)
                    .offset(x: state.offsetX, y: state.offsetY)
            } keyframes: { _ in
                KeyframeTrack(\.offsetY) {
                    CubicKeyframe(-58, duration: Self.duration)
                }
                KeyframeTrack(\.offsetX) {
                    CubicKeyframe(word.drift, duration: Self.duration)
                }
                KeyframeTrack(\.scale) {
                    CubicKeyframe(1.15, duration: Self.duration / 2)
                    CubicKeyframe(1, duration: Self.duration / 2)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: Self.duration * 0.6)
                    LinearKeyframe(0, duration: Self.duration * 0.4)
                }
            }
            .offset(y: -6)
            .task {
                isFlying = true
                try? await Task.sleep(for: .seconds(Self.duration))
                onFinish()
            }
    }
}
