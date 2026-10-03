import AppKit

/// 挿入先に送信のキー(Enter)を送る。
protocol SubmitKeySending {
    func sendSubmitKey(to target: InsertionTarget) async
}

/// Enter のキーのイベントを送り出す。
protocol SubmitKeyPosting {
    func postSubmitKey()
}

/// いまキーボードで押されている修飾キーの読み取り。
protocol ModifierKeyStateReading {
    var pressedModifiers: CGEventFlags { get }
}

/// いま前面にあるアプリの読み取り。
protocol FrontmostApplicationReading {
    var frontmostProcessIdentifier: pid_t? { get }
}

struct CGEventSubmitKeyPoster: SubmitKeyPosting {
    static func makeEvents() -> (keyDown: CGEvent, keyUp: CGEvent)? {
        guard let pair = KeyEventPair(keyCode: CGKeyCode(KeyCode.returnKey), flags: []) else { return nil }
        return (pair.keyDown, pair.keyUp)
    }

    func postSubmitKey() {
        KeyEventPair(keyCode: CGKeyCode(KeyCode.returnKey), flags: [])?.post()
    }
}

struct SystemModifierKeyState: ModifierKeyStateReading {
    var pressedModifiers: CGEventFlags {
        CGEventSource.flagsState(.hidSystemState).intersection([.maskShift, .maskCommand, .maskControl, .maskAlternate])
    }
}

struct WorkspaceFrontmostApplication: FrontmostApplicationReading {
    var frontmostProcessIdentifier: pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }
}

/// 修飾キーが離れるのを待ち、前面のアプリが挿入先のままなら Enter を1回送る。
struct EnterKeySender: SubmitKeySending {
    private let poster: SubmitKeyPosting
    private let modifierState: ModifierKeyStateReading
    private let frontmostApp: FrontmostApplicationReading
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
        for _ in 0..<maxPolls {
            if modifierState.pressedModifiers.isEmpty {
                break
            }
            try? await Task.sleep(for: pollInterval)
        }
        guard frontmostApp.frontmostProcessIdentifier == target.processIdentifier else { return }
        poster.postSubmitKey()
    }
}
