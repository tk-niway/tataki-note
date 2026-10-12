import AppKit
import SwiftUI

/// パネルの外に出すトースト。
protocol InsertionToastPresenting: AnyObject {
    /// パネルがあった枠の場所に文を出し、決まった時間で消す。出ているときは文を替えて時間を数え直す。
    func show(_ message: String, around panelFrame: CGRect)
    /// 出ているトーストをすぐ消す。
    func dismiss()
}

/// トーストの窓を出して、決まった時間で消す。
final class InsertionToastController: InsertionToastPresenting {
    private let sleep: (Duration) async -> Void
    private let announce: (String) -> Void
    private var generation = 0

    /// 今出している文。出ていなければ nil。
    private(set) var message: String?
    /// トーストの窓。まだ一度も出していなければ nil。
    private(set) var toastWindow: PanelToastWindow?

    init(
        sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        announce: @escaping (String) -> Void = { AccessibilityNotification.Announcement($0).post() }
    ) {
        self.sleep = sleep
        self.announce = announce
    }

    func show(_ message: String, around panelFrame: CGRect) {
        generation += 1
        let token = generation
        self.message = message
        let window = toastWindow ?? PanelToastWindow()
        toastWindow = window
        let size = window.present(message: message)
        let center = CGPoint(x: panelFrame.midX, y: panelFrame.midY)
        let visibleFrame = NSScreen.screens.first { $0.frame.contains(center) }?.visibleFrame
        window.setFrame(
            InsertionToast.frame(toastSize: size, panelFrame: panelFrame, visibleFrame: visibleFrame),
            display: true
        )
        window.orderFrontRegardless()
        announce(message)
        let sleep = self.sleep
        Task { [weak self] in
            await sleep(InsertionToast.duration)
            guard let self, self.generation == token else { return }
            self.hide()
        }
    }

    func dismiss() {
        generation += 1
        hide()
    }

    private func hide() {
        message = nil
        toastWindow?.orderOut(nil)
    }
}
