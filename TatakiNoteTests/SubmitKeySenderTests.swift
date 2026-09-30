import AppKit
import Testing
@testable import TatakiNote

/// @note p0-1092
@MainActor
final class SubmitKeyPosterStub: SubmitKeyPosting {
    /// @note p0-1093
    var onPost: (() -> Void)?
    private(set) var postCount = 0

    func postSubmitKey() {
        postCount += 1
        onPost?()
    }
}

/// @note p0-1094
@MainActor
final class ModifierKeyStateStub: ModifierKeyStateReading {
    private let pressed: CGEventFlags
    private let pressedReads: Int
    private(set) var readCount = 0

    init(pressed: CGEventFlags, pressedReads: Int) {
        self.pressed = pressed
        self.pressedReads = pressedReads
    }

    var pressedModifiers: CGEventFlags {
        readCount += 1
        return readCount <= pressedReads ? pressed : []
    }

    /// @note p0-1095
    var hasReturnedEmpty: Bool {
        readCount > pressedReads
    }
}

/// @note p0-1096
@MainActor
final class FrontmostApplicationStub: FrontmostApplicationReading {
    private let provide: () -> pid_t?
    private(set) var readCount = 0

    init(_ provide: @escaping () -> pid_t?) {
        self.provide = provide
    }

    var frontmostProcessIdentifier: pid_t? {
        readCount += 1
        return provide()
    }
}

@MainActor
struct SubmitKeySenderTests {
    private let target = InsertionTarget(processIdentifier: 101, bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit")
    /// @note p0-1097
    private let otherApp: pid_t = 202

    // MARK: - 送る Enter のイベント

    @Test("AC-6: 送信の Enter は Return のキーコードで、Shift・⌘・Control・Option のどれも付いていない(イベントは作るだけで送らない)")
    func submitEventsAreReturnWithoutModifiers() throws {
        let events = try #require(CGEventSubmitKeyPoster.makeEvents())
        #expect(KeyCode.returnKey == 36)

        let cases: [(CGEvent, CGEventType, String)] = [
            (events.keyDown, .keyDown, "keyDown"),
            (events.keyUp, .keyUp, "keyUp"),
        ]
        for (event, type, label) in cases {
            #expect(event.type == type, "\(label)")
            #expect(event.getIntegerValueField(.keyboardEventKeycode) == Int64(KeyCode.returnKey), "\(label)")
            #expect(event.flags.intersection([.maskShift, .maskCommand, .maskControl, .maskAlternate]).isEmpty, "\(label)")
        }
    }

    // MARK: - 修飾キーの待ち

    @Test("AC-7: 修飾キーが押されている間は Enter を送らず、離れてから1回だけ送る")
    func waitsUntilModifiersAreReleased() async {
        let poster = SubmitKeyPosterStub()
        let modifierState = ModifierKeyStateStub(pressed: [.maskCommand, .maskShift], pressedReads: 3)
        var releasedWhenPosted: [Bool] = []
        poster.onPost = { releasedWhenPosted.append(modifierState.hasReturnedEmpty) }
        let sender = EnterKeySender(
            poster: poster,
            modifierState: modifierState,
            frontmostApp: FrontmostApplicationStub { target.processIdentifier },
            pollInterval: .zero,
            maxPolls: 25
        )

        await sender.sendSubmitKey(to: target)

        #expect(poster.postCount == 1)
        // @note p0-1098
        #expect(releasedWhenPosted == [true])
        // @note p0-1099
        #expect(modifierState.readCount == 4)
    }

    @Test("AC-7: 修飾キーが最初から離れていれば、待たずに1回送る")
    func sendsImmediatelyWhenNoModifierIsPressed() async {
        let poster = SubmitKeyPosterStub()
        let modifierState = ModifierKeyStateStub(pressed: [.maskShift], pressedReads: 0)
        let sender = EnterKeySender(
            poster: poster,
            modifierState: modifierState,
            frontmostApp: FrontmostApplicationStub { target.processIdentifier },
            pollInterval: .zero,
            maxPolls: 25
        )

        await sender.sendSubmitKey(to: target)

        #expect(poster.postCount == 1)
        #expect(modifierState.readCount == 1)
    }

    @Test("AC-7: 修飾キーが離れないまま上限の回数を過ぎたら、そこで打ち切って1回送る")
    func sendsAfterMaxPollsWhenModifiersStayPressed() async {
        let poster = SubmitKeyPosterStub()
        let modifierState = ModifierKeyStateStub(pressed: [.maskCommand], pressedReads: .max)
        let sender = EnterKeySender(
            poster: poster,
            modifierState: modifierState,
            frontmostApp: FrontmostApplicationStub { target.processIdentifier },
            pollInterval: .zero,
            maxPolls: 5
        )

        await sender.sendSubmitKey(to: target)

        #expect(poster.postCount == 1)
        #expect(modifierState.hasReturnedEmpty == false)
        #expect(modifierState.readCount == 5)
    }

    // MARK: - 送る直前の前面のアプリの確認

    @Test("AC-16: 修飾キーの待ちの間に前面のアプリが挿入先でなくなったら、Enter を送らない")
    func doesNotSendWhenFrontmostChangesWhileWaiting() async {
        let poster = SubmitKeyPosterStub()
        let modifierState = ModifierKeyStateStub(pressed: [.maskCommand], pressedReads: 3)
        // @note p0-1100
        let frontmostApp = FrontmostApplicationStub {
            modifierState.hasReturnedEmpty ? otherApp : target.processIdentifier
        }
        let sender = EnterKeySender(
            poster: poster,
            modifierState: modifierState,
            frontmostApp: frontmostApp,
            pollInterval: .zero,
            maxPolls: 25
        )

        await sender.sendSubmitKey(to: target)

        #expect(poster.postCount == 0)
        #expect(frontmostApp.readCount >= 1)
    }

    @Test("AC-16: 前面のアプリが分からない・最初から挿入先でないときも、Enter を送らない")
    func doesNotSendWhenFrontmostIsUnknownOrOtherApp() async {
        let scenarios: [(String, pid_t?)] = [
            ("前面のアプリが分からない", nil),
            ("最初から別のアプリが前面", otherApp),
        ]
        for (name, frontmost) in scenarios {
            let poster = SubmitKeyPosterStub()
            let frontmostApp = FrontmostApplicationStub { frontmost }
            let sender = EnterKeySender(
                poster: poster,
                modifierState: ModifierKeyStateStub(pressed: [], pressedReads: 0),
                frontmostApp: frontmostApp,
                pollInterval: .zero,
                maxPolls: 25
            )

            await sender.sendSubmitKey(to: target)

            #expect(poster.postCount == 0, "\(name)")
            #expect(frontmostApp.readCount == 1, "\(name)")
        }
    }
}
