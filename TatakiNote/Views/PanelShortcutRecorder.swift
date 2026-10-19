import SwiftUI

/// 確定+挿入キー・確定+送信キーの記録ボックス。
struct PanelShortcutRecorder: View {
    let display: PanelShortcutRecorderDisplay
    let feedback: RecorderFeedback?
    let onBeginRecording: () -> Void
    let onRecord: (PanelShortcutCandidate) -> Bool
    let onClear: () -> Void
    let onEndRecording: () -> Void
    let identifier: String
    let accessibilityLabel: String

    @Environment(\.isAppAnimationReduced) private var reduceMotion
    @State private var capsAppearCount = 0

    private static let cornerRadius: CGFloat = 8
    private static let minimumWidth: CGFloat = 160
    private static let height: CGFloat = 30

    private var isRecording: Bool { display == .recording }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: beginRecording) {
                face
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: accessibilityLabel))
            .accessibilityValue(Text(verbatim: display.accessibilityValue))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(identifier)
            if case .registered = display {
                clearButton
            }
        }
        .frame(minWidth: Self.minimumWidth)
        .frame(height: Self.height)
        .background(RoundedRectangle(cornerRadius: Self.cornerRadius).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .strokeBorder(
                    isRecording ? Color.accentColor : Color(nsColor: .separatorColor),
                    lineWidth: isRecording ? 1.5 : 1
                )
        )
        .overlay { pulse }
        .background(
            ShortcutRecordingMonitor(
                isRecording: isRecording,
                onRecord: onRecord,
                onClear: onClear,
                onEndRecording: onEndRecording
            )
        )
        .recorderFeedback(feedback)
        .onChange(of: feedback) { _, newValue in
            if newValue?.kind == .accepted {
                capsAppearCount += 1
            }
        }
    }

    private func beginRecording() {
        guard !isRecording else { return }
        onBeginRecording()
    }

    @ViewBuilder private var face: some View {
        switch display {
        case .recording:
            Text("ショートカットを押す")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        case .registered(_, let caps):
            HStack(spacing: 3) {
                ForEach(Array(caps.enumerated()), id: \.offset) { index, cap in
                    RecorderKeyCap(text: cap, index: index, appearCount: capsAppearCount, reduceMotion: reduceMotion)
                }
            }
            .padding(.trailing, 22)
        case .unregistered:
            Text("登録なし")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var clearButton: some View {
        Button(action: onClear) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: Self.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 4)
        .accessibilityLabel(Text(verbatim: "\(accessibilityLabel) の登録を消す"))
        .accessibilityIdentifier("\(identifier).clear")
    }

    @ViewBuilder private var pulse: some View {
        if isRecording, !reduceMotion {
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .phaseAnimator([false, true]) { ring, isExpanded in
                    ring
                        .padding(isExpanded ? -7 : 0)
                        .opacity(isExpanded ? 0 : 0.5)
                } animation: { isExpanded in
                    isExpanded ? .easeOut(duration: 1.2) : nil
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct RecorderKeyCap: View {
    let text: String
    let index: Int
    let appearCount: Int
    let reduceMotion: Bool

    var body: some View {
        KeyCapView(text: text)
            .keyframeAnimator(initialValue: 1.0, trigger: appearCount) { content, scale in
                content
                    .scaleEffect(scale)
                    .opacity(min(1, max(0, (scale - 0.5) * 2)))
            } keyframes: { _ in
                KeyframeTrack {
                    MoveKeyframe(reduceMotion ? 1.0 : 0.5)
                    LinearKeyframe(reduceMotion ? 1.0 : 0.5, duration: 0.05 * Double(index) + 0.001)
                    SpringKeyframe(1.0, duration: 0.25, spring: .snappy)
                }
            }
    }
}

private struct RecorderFeedbackEffect: ViewModifier {
    let feedback: RecorderFeedback?

    @Environment(\.isAppAnimationReduced) private var reduceMotion
    @State private var acceptedCount = 0
    @State private var rejectedCount = 0

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: 1.0, trigger: acceptedCount) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(reduceMotion ? 1.0 : 1.1, duration: 0.18)
                    LinearKeyframe(reduceMotion ? 1.0 : 0.96, duration: 0.14)
                    LinearKeyframe(1.0, duration: 0.12)
                }
            }
            .keyframeAnimator(initialValue: 0.0, trigger: rejectedCount) { view, offsetX in
                view.offset(x: offsetX)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(reduceMotion ? 0.0 : -6.0, duration: 0.08)
                    LinearKeyframe(reduceMotion ? 0.0 : 6.0, duration: 0.08)
                    LinearKeyframe(reduceMotion ? 0.0 : -3.0, duration: 0.08)
                    LinearKeyframe(0.0, duration: 0.08)
                }
            }
            .onChange(of: feedback) { _, newValue in
                switch newValue?.kind {
                case .accepted: acceptedCount += 1
                case .rejected: rejectedCount += 1
                case nil: break
                }
            }
    }
}

extension View {
    /// 受け付けた合図で弾み、受け付けなかった合図で横に揺れる。
    func recorderFeedback(_ feedback: RecorderFeedback?) -> some View {
        modifier(RecorderFeedbackEffect(feedback: feedback))
    }
}
