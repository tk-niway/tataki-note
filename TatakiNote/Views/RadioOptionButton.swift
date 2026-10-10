import AppKit
import SwiftUI

/// 選択肢ごとに押せる・押せないを切り替えられるラジオボタン。
struct RadioOptionButton: NSViewRepresentable {
    let title: String
    let isOn: Bool
    let isEnabled: Bool
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(radioButtonWithTitle: title, target: context.coordinator, action: #selector(Coordinator.clicked))
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.title = title
        button.isEnabled = isEnabled
        button.state = isOn ? .on : .off
    }

    /// ボタンが押されたときに `action` を呼ぶ。
    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func clicked() {
            action()
        }
    }
}
