import SwiftUI

/// アクセシビリティの許可の案内。
struct PermissionGuideView: View {
    @Bindable var model: PermissionGuideModel
    let onClose: () -> Void
    let onProceed: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch model.state {
            case .granted:
                HStack(alignment: .top, spacing: 16) {
                    PermissionGuideIcon(isGranted: true)
                    PermissionGuideStatus(isGranted: true)
                }
            case .readyForTutorial:
                HStack(alignment: .top, spacing: 16) {
                    PermissionGuideIcon(isGranted: true)
                    VStack(alignment: .leading, spacing: 14) {
                        PermissionGuideStatus(isGranted: true)
                        Text("続けて、TatakiNote の使い方を練習しましょう。")
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("permissionGuide.readyForTutorial")
                    }
                }
            case .notGranted(let reason):
                HStack(alignment: .top, spacing: 16) {
                    PermissionGuideIcon(isGranted: false)
                    VStack(alignment: .leading, spacing: 14) {
                        if reason == .commitDenied {
                            PermissionGuideDraftKept()
                        }
                        PermissionGuideStatus(isGranted: false)
                        PermissionGuideSteps()
                        if model.showsTutorialNote {
                            PermissionGuideTutorialNote()
                        }
                    }
                }
            }
            PermissionGuideButtons(
                buttons: model.buttons,
                onOpenSystemSettings: { model.openSystemSettings() },
                onClose: onClose,
                onProceed: onProceed
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 20)
        .frame(width: 480, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 許可の案内の左のアイコン(装飾)。
struct PermissionGuideIcon: View {
    let isGranted: Bool

    var body: some View {
        if isGranted {
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .green)
                .font(.system(size: 32))
                .accessibilityHidden(true)
        } else {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 32))
                .accessibilityHidden(true)
        }
    }
}

/// 許可の有無の表示。
struct PermissionGuideStatus: View {
    let isGranted: Bool
    var identifier: String = "permissionGuide.status"

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if isGranted {
                Text("アクセシビリティの許可があります。")
                    .font(.headline)
                Text("文章を挿入できます。")
            } else {
                Text("アクセシビリティの許可がありません。")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("TatakiNote が文章を入力欄に挿入するには許可が必要です。")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

private struct PermissionGuideDraftKept: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("挿入できませんでした。")
                    .font(.headline)
                Text("書いた文章はパネルに下書きとして残っています。許可した後に、パネルを開いてもう一度確定してください。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("permissionGuide.draftKept")
    }
}

/// 許可の手順の表示。
struct PermissionGuideSteps: View {
    var identifier: String = "permissionGuide.steps"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("許可の手順")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            PermissionGuideStep(number: "1.", text: Text("下の「システム設定を開く」を押します。"))
            PermissionGuideStep(
                number: "2.",
                text: Text("「プライバシーとセキュリティ」→「アクセシビリティ」で、TatakiNote のスイッチをオンにします。")
            )
            PermissionGuideStep(
                number: "3.",
                text: Text("一覧に TatakiNote が無いときは、「+」を押して、アプリケーションフォルダの TatakiNote を追加します。")
            )
            Text("オンにすると、数秒のうちにこの画面の表示が変わります。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

private struct PermissionGuideStep: View {
    let number: String
    let text: Text

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(verbatim: number)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .leading)
            text
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PermissionGuideTutorialNote: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "info.circle")
                .accessibilityHidden(true)
            Text("チュートリアルは、設定の「アプリ情報」からいつでも開けます。")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("permissionGuide.tutorialNote")
    }
}

private struct PermissionGuideButtons: View {
    let buttons: [PermissionGuideButton]
    let onOpenSystemSettings: () -> Void
    let onClose: () -> Void
    let onProceed: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Spacer()
            ForEach(buttons, id: \.self) { button in
                switch button {
                case .close:
                    Button("閉じる", action: onClose)
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("permissionGuide.close")
                case .openSystemSettings:
                    Button("システム設定を開く", action: onOpenSystemSettings)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("permissionGuide.openSystemSettings")
                case .next:
                    Button("次へ", action: onProceed)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("permissionGuide.next")
                }
            }
        }
    }
}
