import AppKit

/// @note p0-119
protocol SubmitKeySending {
    func sendSubmitKey(to target: InsertionTarget) async
}

/// @note p0-120
protocol SubmitKeyPosting {
    func postSubmitKey()
}

/// @note p0-121
protocol ModifierKeyStateReading {
    var pressedModifiers: CGEventFlags { get }
}

/// @note p0-122
protocol FrontmostApplicationReading {
    var frontmostProcessIdentifier: pid_t? { get }
}

struct CGEventSubmitKeyPoster: SubmitKeyPosting {
    /// @note p0-123
    static func makeEvents() -> (keyDown: CGEvent, keyUp: CGEvent)? {
        let source = CGEventSource(stateID: .combinedSessionState)
        let returnKey = CGKeyCode(KeyCode.returnKey)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: false)
        else { return nil }
        // @note p0-124
        keyDown.flags = []
        keyUp.flags = []
        return (keyDown, keyUp)
    }

    func postSubmitKey() {
        guard let events = Self.makeEvents() else { return }
        events.keyDown.post(tap: .cghidEventTap)
        events.keyUp.post(tap: .cghidEventTap)
    }
}

struct SystemModifierKeyState: ModifierKeyStateReading {
    /// @note p0-125
    var pressedModifiers: CGEventFlags {
        CGEventSource.flagsState(.hidSystemState).intersection([.maskShift, .maskCommand, .maskControl, .maskAlternate])
    }
}

struct WorkspaceFrontmostApplication: FrontmostApplicationReading {
    var frontmostProcessIdentifier: pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }
}

/// @note p0-126
struct EnterKeySender: SubmitKeySending {
    private let poster: SubmitKeyPosting
    private let modifierState: ModifierKeyStateReading
    private let frontmostApp: FrontmostApplicationReading
    /// @note p0-127
    private let pollInterval: Duration
    private let maxPolls: Int

    init(
        poster: SubmitKeyPosting = CGEventSubmitKeyPoster(),
        modifierState: ModifierKeyStateReading = SystemModifierKeyState(),
        frontmostApp: FrontmostApplicationReading = WorkspaceFrontmostApplication(),
        pollInterval: Duration = .milliseconds(20),
        maxPolls: Int = 25
    ) {
        self.poster = poster
        self.modifierState = modifierState
        self.frontmostApp = frontmostApp
        self.pollInterval = pollInterval
        self.maxPolls = maxPolls
    }

    func sendSubmitKey(to target: InsertionTarget) async {
        // @note p0-128
        for _ in 0..<maxPolls {
            if modifierState.pressedModifiers.isEmpty {
                break
            }
            try? await Task.sleep(for: pollInterval)
        }
        // @note p0-129
        guard frontmostApp.frontmostProcessIdentifier == target.processIdentifier else { return }
        poster.postSubmitKey()
    }
}
