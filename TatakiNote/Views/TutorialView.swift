import SwiftUI

/// チュートリアルの画面。
struct TutorialView: View {
    @Bindable var model: TutorialModel
    let onClose: () -> Void

    var body: some View {
        Group {
            if model.isShowingSkipNotice {
                TutorialSkipNotice(onClose: onClose)
            } else {
                TutorialContent(model: model, onClose: onClose)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 20)
        .frame(
            width: TutorialWindowController.contentSize.width,
            height: TutorialWindowController.contentSize.height,
            alignment: .topLeading
        )
    }
}

private struct TutorialContent: View {
    @Bindable var model: TutorialModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(TutorialModel.introduction)
                .fixedSize(horizontal: false, vertical: true)
            if model.isShowingOtherTargetWarning {
                TutorialOtherTargetWarning()
            }
            VStack(spacing: 4) {
                ForEach(TutorialStep.allCases, id: \.self) { step in
                    TutorialStepRow(step: step, model: model)
                }
            }
            PracticeChatView(model: model)
            HStack {
                Spacer()
                if model.showsFinishButton {
                    Button("完了", action: onClose)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("tutorial.finish")
                } else {
                    Button("スキップ") { model.skip() }
                        .accessibilityIdentifier("tutorial.skip")
                }
            }
        }
    }
}

private struct PracticeChatView: View {
    @Bindable var model: TutorialModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("練習用のチャット")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 10) {
                    KeyHint(key: "↩", label: String(localized: "送信"), showsLabel: true)
                    KeyHint(key: "⇧↩", label: String(localized: "改行"), showsLabel: true)
                }
            }
            VStack(spacing: 0) {
                PracticeChatMessageList(messages: model.chat.messages)
                Divider()
                PracticeTextEditor(
                    text: $model.practiceText,
                    focusRequest: model.practiceFocusRequest,
                    placeholder: PracticeChat.inputPlaceholder,
                    onSend: { model.sendPracticeMessage($0) }
                )
                .frame(height: 56)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
        }
        .frame(maxHeight: .infinity)
    }
}

private struct PracticeChatMessageList: View {
    let messages: [PracticeChatMessage]

    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { message in
                            PracticeChatBubble(message: message, maxWidth: proxy.size.width * 0.75)
                                .id(message.id)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: messages.count) {
                    guard let last = messages.last else { return }
                    withAnimation { reader.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .frame(minHeight: 160, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tutorial.chat.messages")
    }
}

private struct PracticeChatBubble: View {
    let message: PracticeChatMessage
    let maxWidth: CGFloat

    var body: some View {
        switch message.kind {
        case .example:
            ownBubble(identifier: "tutorial.chat.message.example", showsCaption: true)
        case .sent:
            ownBubble(identifier: "tutorial.chat.message.sent", showsCaption: false)
        case .reply:
            replyBubble
        }
    }

    private func ownBubble(identifier: String, showsCaption: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(verbatim: message.text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.white)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: maxWidth, alignment: .trailing)
            if showsCaption {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                        .accessibilityHidden(true)
                    Text(verbatim: PracticeChat.exampleCaption)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: maxWidth, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private var replyBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(PracticeChat.replyLabel, systemImage: "text.bubble")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(verbatim: message.text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(nsColor: .quaternaryLabelColor), in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: maxWidth, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tutorial.chat.message.reply")
    }
}

private struct TutorialSkipNotice: View {
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 32))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("チュートリアルをスキップしました。")
                        .font(.headline)
                    Text("チュートリアルは、設定の「アプリ情報」からいつでも開けます。")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("tutorial.skipNotice")
            Spacer()
            HStack {
                Spacer()
                Button("閉じる", action: onClose)
                    .accessibilityIdentifier("tutorial.skipNotice.close")
            }
        }
    }
}

private struct TutorialOtherTargetWarning: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
                .accessibilityHidden(true)
            Text(TutorialModel.otherTargetWarning)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.orange.opacity(0.3)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tutorial.otherTargetWarning")
    }
}

private struct TutorialStepRow: View {
    let step: TutorialStep
    let model: TutorialModel

    var body: some View {
        let isCompleted = model.isCompleted(step)
        let isCurrent = model.currentStep == step
        HStack(alignment: .top, spacing: 10) {
            TutorialStepMarker(number: step.rawValue + 1, isCompleted: isCompleted, isCurrent: isCurrent)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? .primary : .secondary)
                if isCurrent {
                    detail
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isCurrent ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityValue(isCompleted ? String(localized: "完了") : String(localized: "未完了"))
        .accessibilityIdentifier(identifier)
    }

    private var title: LocalizedStringKey {
        switch step {
        case .openPanel: "パネルを開く"
        case .writeWithNewline: "Enter で改行しながら書く"
        case .send: "送る"
        case .nextSteps: "次の一歩"
        }
    }

    private var identifier: String {
        switch step {
        case .openPanel: "tutorial.step.openPanel"
        case .writeWithNewline: "tutorial.step.writeWithNewline"
        case .send: "tutorial.step.send"
        case .nextSteps: "tutorial.step.nextSteps"
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch step {
        case .openPanel:
            Text(model.openPanelInstruction)
                .fixedSize(horizontal: false, vertical: true)
        case .writeWithNewline:
            Text(model.writeInstruction)
                .fixedSize(horizontal: false, vertical: true)
        case .send:
            Text(model.sendInstruction)
                .fixedSize(horizontal: false, vertical: true)
        case .nextSteps:
            TutorialNextSteps()
        }
    }
}

private struct TutorialNextSteps: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("これで基本の流れは終わりです。慣れてきたら、次の使い方も試してみてください。")
                .fixedSize(horizontal: false, vertical: true)
            ForEach(TutorialNextStepIntroduction.allCases, id: \.self) { introduction in
                TutorialIntroduction(
                    heading: Text(introduction.heading),
                    text: Text(introduction.text)
                )
            }
        }
    }
}

private struct TutorialIntroduction: View {
    let heading: Text
    let text: Text

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: "•")
                .foregroundStyle(.secondary)
            (heading.bold() + Text(verbatim: " — ") + text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TutorialStepMarker: View {
    let number: Int
    let isCompleted: Bool
    let isCurrent: Bool

    var body: some View {
        Group {
            if isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .green)
                    .font(.system(size: 20))
            } else if isCurrent {
                Text(verbatim: "\(number)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .background(Circle().fill(Color.accentColor).frame(width: 20, height: 20))
            } else {
                Text(verbatim: "\(number)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .background(Circle().strokeBorder(.secondary).frame(width: 20, height: 20))
            }
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }
}
