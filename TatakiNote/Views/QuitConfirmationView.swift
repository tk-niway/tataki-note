import SwiftUI

/// ⌘Q で終了する前の確かめ。
struct QuitConfirmationView: View {
    @Bindable var model: QuitConfirmationModel
    let onQuit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TatakiNote を終了しますか?")
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("終了すると、ホットキーでパネルを開けなくなります。書きかけは履歴に残ります。")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 4) {
                        Toggle("今後は確かめない", isOn: $model.suppressesFuture)
                            .toggleStyle(.checkbox)
                            .keyboardShortcut("d", modifiers: .command)
                            .accessibilityIdentifier("quitConfirmation.suppress")
                        KeyCapRow(alternatives: [["⌘", "D"]])
                            .accessibilityHidden(true)
                    }
                }
            }
            HStack(spacing: 12) {
                Spacer()
                Button("キャンセル", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("quitConfirmation.cancel")
                Button("終了", action: onQuit)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("quitConfirmation.quit")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 20)
        .frame(width: 420, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
