import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
final class PanelShakerSpy: PanelShaking {
    private(set) var shakeCount = 0
    private(set) var stopCount = 0
    private(set) var windowVisibilityAtStop: [Bool] = []

    func shake(_ window: NSWindow) {
        shakeCount += 1
    }

    func stop(_ window: NSWindow) {
        stopCount += 1
        windowVisibilityAtStop.append(window.isVisible)
    }
}

@MainActor
final class BeepSpy {
    private(set) var count = 0

    func beep() {
        count += 1
    }
}

@MainActor
final class HideApplicationCounter {
    private(set) var count = 0

    func record() {
        count += 1
    }
}

@MainActor
final class HeldSleeper {
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func sleep(_ duration: Duration) async {
        await withCheckedContinuation { waiting.append($0) }
    }

    func releaseAll() {
        let continuations = waiting
        waiting = []
        for continuation in continuations {
            continuation.resume()
        }
    }
}

@MainActor
final class FakePanelFrameAnimator: PanelFrameAnimating {
    struct Call {
        let window: NSWindow
        let frame: NSRect
        let duration: TimeInterval
        let curve: PanelMotionCurve
        let windowFrame: NSRect
        let canBecomeKey: Bool
        let ignoresMouseEvents: Bool
        let isVisible: Bool
    }

    private(set) var calls: [Call] = []
    private(set) var jumps: [NSRect] = []
    private var completions: [(() -> Void)?] = []
    var completesPendingOnJump = false

    func animate(_ window: NSWindow, to frame: NSRect, duration: TimeInterval, curve: PanelMotionCurve, completion: @escaping () -> Void) {
        calls.append(
            Call(
                window: window,
                frame: frame,
                duration: duration,
                curve: curve,
                windowFrame: window.frame,
                canBecomeKey: window.canBecomeKey,
                ignoresMouseEvents: window.ignoresMouseEvents,
                isVisible: window.isVisible
            )
        )
        completions.append(completion)
    }

    func jump(_ window: NSWindow, to frame: NSRect) {
        jumps.append(frame)
        if completesPendingOnJump {
            for index in completions.indices {
                guard let completion = completions[index] else { continue }
                completions[index] = nil
                completion()
            }
        }
        window.setFrame(frame, display: false)
    }

    func finish(_ index: Int, moving: Bool = true) {
        guard completions.indices.contains(index), let completion = completions[index] else { return }
        completions[index] = nil
        if moving {
            calls[index].window.setFrame(calls[index].frame, display: false)
        }
        completion()
    }

    func isFinished(_ index: Int) -> Bool {
        completions.indices.contains(index) && completions[index] == nil
    }
}
