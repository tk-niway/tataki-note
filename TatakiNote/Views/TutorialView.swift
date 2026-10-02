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
        .frame(width: 520, height: 560, alignment: .topLeading)
    }
}

private struct TutorialContent: View {
    @Bindable var model: TutorialModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("パネルで書いて、元の入力欄に入れるまでを、下の練習用の入力欄で1段階ずつ試してみましょう。")
                .fixedSize(horizontal: false, vertical: true)
            if model.isShowingOtherTargetWarning {
                TutorialOtherTargetWarning()
            }
            VStack(spacing: 4) {
                ForEach(TutorialStep.allCases, id: \.self) { step in
                    TutorialStepRow(step: step, model: model)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("練習用の入力欄")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                PracticeTextEditor(text: $model.practiceText, focusRequest: model.practiceFocusRequest)
                    .frame(height: 96)
            }
            Spacer(minLength: 0)
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
            Text("パネルの挿入先が別のアプリになっています。確定せずにパネルを閉じ、練習用の入力欄をクリックしてから開き直してください。")
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
        case .insert: "確定して入力欄に入れる"
        case .nextSteps: "次の一歩"
        }
    }

    private var identifier: String {
        switch step {
        case .openPanel: "tutorial.step.openPanel"
        case .writeWithNewline: "tutorial.step.writeWithNewline"
        case .insert: "tutorial.step.insert"
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
            Text("パネルでは Enter が改行になります。途中で送信されることはありません。2行以上の文章を書いてみましょう。")
                .fixedSize(horizontal: false, vertical: true)
        case .insert:
            Text(model.insertInstruction)
                .fixedSize(horizontal: false, vertical: true)
        case .nextSteps:
            TutorialNextSteps(model: model)
        }
    }
}

private struct TutorialNextSteps: View {
    let model: TutorialModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("これで基本の流れは終わりです。慣れてきたら、次の使い方も試してみてください。")
                .fixedSize(horizontal: false, vertical: true)
            TutorialIntroduction(
                heading: Text("自動表示"),
                text: Text("設定の「一般」で、入力欄を選ぶだけでパネルを出せます。")
            )
            TutorialIntroduction(
                heading: Text("確定+送信"),
                text: Text(model.commitAndSendIntroduction)
            )
            TutorialIntroduction(
                heading: Text("ホットキーの変更"),
                text: Text("設定の「一般」の「パネルを開く・閉じる」で変えられます。")
            )
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
