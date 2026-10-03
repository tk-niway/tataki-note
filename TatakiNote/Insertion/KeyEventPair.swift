import CoreGraphics

/// キーを押して離す1組のイベント。
struct KeyEventPair {
    let keyDown: CGEvent
    let keyUp: CGEvent

    /// `combinedSessionState` の source で、決めた修飾キーを付けた1組を作る。作れなければ nil。
    init?(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return nil }
        keyDown.flags = flags
        keyUp.flags = flags
        self.keyDown = keyDown
        self.keyUp = keyUp
    }

    /// `.cghidEventTap` に keyDown・keyUp の順で送る。
    func post() {
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
