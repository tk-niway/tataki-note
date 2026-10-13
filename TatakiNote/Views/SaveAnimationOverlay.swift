import SwiftUI

/// 開閉ボタンの位置を伝える値。
struct SidebarToggleAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// 保存した下書きを表す書類のアイコンを、本文の中央から開閉ボタンへ飛ばして吸い込ませる。
struct SaveAnimationOverlay: View {
    let model: SaveAnimationModel
    let toggleAnchor: Anchor<CGRect>?

    var body: some View {
        GeometryReader { proxy in
            if let toggleAnchor, let flight = toggleFlight {
                let target = proxy[toggleAnchor]
                FlyingDocumentIcon(
                    start: CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2),
                    end: CGPoint(x: target.midX, y: target.midY),
                    isAbsorbing: isArrived
                )
                .id(flight.id)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var toggleFlight: SaveFlight? {
        switch model.phase {
        case .idle:
            nil
        case .flying(let flight), .arrived(let flight):
            flight.destination == .sidebarToggle ? flight : nil
        }
    }

    private var isArrived: Bool {
        if case .arrived = model.phase { return true }
        return false
    }
}

private struct FlyingDocumentIcon: View {
    let start: CGPoint
    let end: CGPoint
    let isAbsorbing: Bool

    @State private var progress = 0.0

    var body: some View {
        FlightPosition(progress: progress, start: start, end: end)
            .scaleEffect(isAbsorbing ? 0.5 : 1)
            .opacity(isAbsorbing ? 0 : 1)
            .animation(.easeOut(duration: SaveAnimationModel.arrivalDuration.seconds), value: isAbsorbing)
            .onAppear {
                withAnimation(.easeIn(duration: SaveAnimationModel.flyingDuration.seconds)) {
                    progress = 1
                }
            }
    }
}

private struct FlightPosition: View, Animatable {
    var progress: Double
    let start: CGPoint
    let end: CGPoint

    private static let iconSize: CGFloat = 28
    private static let arcHeight: CGFloat = 36
    private static let appearingProgress = 0.06
    private static let startScale = 0.6
    private static let endScale = 0.4

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let appearing = min(1, progress / Self.appearingProgress)
        let scale = Self.startScale + (1 - Self.startScale) * appearing
            - (1 - Self.endScale) * max(0, (progress - Self.appearingProgress) / (1 - Self.appearingProgress))
        icon
            .scaleEffect(scale)
            .opacity(appearing)
            .position(
                x: start.x + (end.x - start.x) * progress,
                y: start.y + (end.y - start.y) * progress - sin(.pi * progress) * Self.arcHeight
            )
    }

    private var icon: some View {
        Image(systemName: "doc.text.fill")
            .font(.system(size: 16))
            .foregroundStyle(.white)
            .frame(width: Self.iconSize, height: Self.iconSize)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.accentColor)
            )
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }
}
