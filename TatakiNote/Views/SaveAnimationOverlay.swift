import SwiftUI

/// 飛び込む先の位置を伝える値。
struct SaveFlightAnchorKey: PreferenceKey {
    static let defaultValue: [SaveFlightDestination: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [SaveFlightDestination: Anchor<CGRect>],
        nextValue: () -> [SaveFlightDestination: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// 着いた回数と、着いた先。着いた先の View だけが弾む。
struct SaveArrival: Equatable {
    var count = 0
    var destination: SaveFlightDestination?
}

extension View {
    /// この View の位置を、保存の演出の飛び込み先として伝える。
    func saveFlightAnchor(_ destination: SaveFlightDestination) -> some View {
        anchorPreference(key: SaveFlightAnchorKey.self, value: .bounds) { [destination: $0] }
    }

    /// 保存した本文の写しが着いたとき、自分が着いた先なら弾ませる。`destination` が nil の View は弾まない。
    func saveArrivalBounce(
        for destination: SaveFlightDestination?,
        arrival: SaveArrival,
        anchor: UnitPoint = .center
    ) -> some View {
        modifier(SaveArrivalBounce(destination: destination, arrival: arrival, anchor: anchor))
    }
}

private struct SaveArrivalBounce: ViewModifier {
    let destination: SaveFlightDestination?
    let arrival: SaveArrival
    let anchor: UnitPoint

    @State private var ownTrigger = 0

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: 1.0, trigger: ownTrigger) { view, scale in
                view.scaleEffect(scale, anchor: anchor)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(1.22, duration: 0.18)
                    CubicKeyframe(0.92, duration: 0.14)
                    CubicKeyframe(1.0, duration: 0.14)
                }
            }
            .onChange(of: arrival) { _, newValue in
                if let destination, newValue.destination == destination {
                    ownTrigger += 1
                }
            }
    }
}

/// 保存した本文の写しを入力欄から飛び込み先へ飛ばし、着いたら粒を散らす。
struct SaveAnimationOverlay: View {
    let model: SaveAnimationModel
    let anchors: [SaveFlightDestination: Anchor<CGRect>]
    let bodyLeadingInset: CGFloat

    var body: some View {
        GeometryReader { proxy in
            if let flight = currentFlight, let anchor = anchors[flight.destination] {
                let target = proxy[anchor]
                let center = CGPoint(x: target.midX, y: target.midY)
                if isArrived {
                    SaveBurstView(center: center)
                        .id(flight.id)
                } else {
                    FlyingTextCard(
                        text: flight.text,
                        cardSize: cardSize(in: proxy.size),
                        start: cardStart(in: proxy.size),
                        end: center
                    )
                    .id(flight.id)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var currentFlight: SaveFlight? {
        switch model.phase {
        case .idle:
            nil
        case .flying(let flight), .arrived(let flight):
            flight
        }
    }

    private var isArrived: Bool {
        if case .arrived = model.phase { return true }
        return false
    }

    private func cardSize(in size: CGSize) -> CGSize {
        CGSize(width: max(120, (size.width - bodyLeadingInset) / 2), height: 56)
    }

    private func cardStart(in size: CGSize) -> CGPoint {
        let card = cardSize(in: size)
        return CGPoint(
            x: bodyLeadingInset + Self.edgeInset + card.width / 2,
            y: PanelMetrics.titleBarHeight + Self.edgeInset / 2 + card.height / 2
        )
    }

    private static let edgeInset: CGFloat = 16
}

private struct FlyingTextCard: View {
    let text: String
    let cardSize: CGSize
    let start: CGPoint
    let end: CGPoint

    @State private var progress = 0.0

    var body: some View {
        FlightPosition(
            progress: progress,
            start: start,
            end: end,
            text: text,
            cardSize: cardSize
        )
        .onAppear {
            withAnimation(.easeInOut(duration: SaveAnimationModel.flyingDuration.seconds)) {
                progress = 1
            }
        }
    }
}

private struct FlightPosition: View, Animatable {
    var progress: Double
    let start: CGPoint
    let end: CGPoint
    let text: String
    let cardSize: CGSize

    @Environment(\.colorScheme) private var colorScheme

    private static let arcHeight: CGFloat = 64
    private static let endScale = 0.04
    private static let fadingProgress = 0.9

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let scale = 1 - (1 - Self.endScale) * progress
        let fade = progress > Self.fadingProgress ? max(0, (1 - progress) / (1 - Self.fadingProgress)) : 1
        card
            .scaleEffect(scale)
            .opacity(fade)
            .position(
                x: start.x + (end.x - start.x) * progress,
                y: start.y + (end.y - start.y) * progress - sin(.pi * progress) * Self.arcHeight
            )
    }

    private var card: some View {
        Text(verbatim: text)
            .font(.system(size: 12))
            .foregroundStyle(.primary)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(width: cardSize.width, height: cardSize.height, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .textBackgroundColor))
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.22 : 0.12))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
    }
}

private struct SaveBurstView: View {
    let center: CGPoint

    var body: some View {
        ZStack {
            ForEach(0..<SaveBurst.particleCount, id: \.self) { index in
                BurstParticle(index: index, center: center)
            }
        }
    }
}

private struct BurstParticle: View {
    let index: Int
    let center: CGPoint

    @State private var isScattered = false

    private static let diameter: CGFloat = 5

    var body: some View {
        let particle = SaveBurst.particle(at: index)
        Circle()
            .fill(Color.accentColor)
            .frame(width: Self.diameter, height: Self.diameter)
            .offset(
                x: isScattered ? CGFloat(cos(particle.angle)) * particle.distance : 0,
                y: isScattered ? CGFloat(sin(particle.angle)) * particle.distance : 0
            )
            .opacity(isScattered ? 0 : 1)
            .position(center)
            .onAppear {
                withAnimation(.easeOut(duration: 0.52 + Double(index % 5) * 0.05)) {
                    isScattered = true
                }
            }
    }
}
