import AppKit
import Testing
@testable import TatakiNote

nonisolated struct QuitKeyScenario: Sendable, CustomTestStringConvertible {
    enum InputSource: String, Sendable, CaseIterable {
        case english
        case romaji
        case kana
        case capsLock
    }

    enum Context: String, Sendable, CaseIterable {
        case panelTyping
        case panelComposing
        case settingsWindow
        case noKeyWindow
    }

    let inputSource: InputSource
    let context: Context
    let showsDockIcon: Bool

    var testDescription: String {
        "\(inputSource.rawValue) / \(context.rawValue) / Dock \(showsDockIcon ? "表示" : "非表示")"
    }

    var characters: String {
        switch inputSource {
        case .english, .romaji: "q"
        case .kana: "た"
        case .capsLock: "Q"
        }
    }

    var modifiersRawValue: UInt {
        var modifiers: NSEvent.ModifierFlags = .command
        if inputSource == .capsLock { modifiers.insert(.capsLock) }
        return modifiers.rawValue
    }

    var isPanelKey: Bool {
        context == .panelTyping || context == .panelComposing
    }

    var hasMarkedText: Bool {
        context == .panelComposing
    }

    static let all: [QuitKeyScenario] = QuitKeyScenario.InputSource.allCases.flatMap { inputSource in
        QuitKeyScenario.Context.allCases.flatMap { context in
            [true, false].map { QuitKeyScenario(inputSource: inputSource, context: context, showsDockIcon: $0) }
        }
    }
}

@MainActor
struct QuitConfirmationModelInputSourceTests {
    private static let keyCodeQ: UInt16 = 12

    private func makeEvent(_ scenario: QuitKeyScenario) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: scenario.modifiersRawValue),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: scenario.characters,
            charactersIgnoringModifiers: scenario.characters,
            isARepeat: false,
            keyCode: Self.keyCodeQ
        ))
    }

    private func isPanelCommitKey(_ event: NSEvent, scenario: QuitKeyScenario) -> Bool {
        let input = PanelKeyInput(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask),
            hasMarkedText: scenario.hasMarkedText,
            characters: event.charactersIgnoringModifiers?.lowercased() ?? ""
        )
        return QuitConfirmation.isPanelCommitKey(
            input,
            isPanelKey: scenario.isPanelKey,
            commitKey: .commandReturn,
            commitAndSendKey: .commandShiftReturn
        )
    }

    private func withModels(
        scenario: QuitKeyScenario,
        confirmsQuit: Bool,
        _ body: (QuitConfirmationModel, QuitConfirmationModel) throws -> Void
    ) throws {
        let defaults = try TemporaryDefaults()
        defer { defaults.remove() }
        let settings = defaults.makeSettings()
        settings.showsDockIcon = scenario.showsDockIcon
        settings.confirmsQuit = confirmsQuit
        let keyModel = QuitConfirmationModel(settings: settings, terminate: {})
        let requestModel = QuitConfirmationModel(settings: settings, terminate: {})
        try body(keyModel, requestModel)
    }

    @Test("AC-31: 入力ソース・文脈・Dock の表示のどれでも、確認がオンなら見張りの経路で確かめ、終了の頼みの経路で終了をやめて確かめる", arguments: QuitKeyScenario.all)
    func confirmsInEveryPath(_ scenario: QuitKeyScenario) throws {
        let event = try makeEvent(scenario)
        let isCommitKey = isPanelCommitKey(event, scenario: scenario)
        #expect(QuitConfirmation.isQuitKeyEvent(event))
        #expect(!isCommitKey)

        try withModels(scenario: scenario, confirmsQuit: true) { keyModel, requestModel in
            let keyAction = keyModel.handleQuitKey(
                isRecordingShortcut: false,
                isPanelCommitKey: isCommitKey,
                isModalRunning: false
            )
            let reply = requestModel.handleTerminationRequest(
                isQuitKeyEvent: QuitConfirmation.isQuitKeyEvent(event),
                isQuitAppleEvent: false,
                isRecordingShortcut: false,
                isPanelCommitKey: isCommitKey,
                isModalRunning: false
            )

            #expect(keyAction == .confirm)
            #expect(keyModel.isConfirming)
            #expect(reply == .cancelAndConfirm)
            #expect(requestModel.isConfirming)
        }
    }

    @Test("AC-31: 確認がオフなら、どの入力ソース・文脈・Dock の表示でも、どちらの経路も終了する", arguments: QuitKeyScenario.all)
    func terminatesInEveryPathWhenOff(_ scenario: QuitKeyScenario) throws {
        let event = try makeEvent(scenario)
        let isCommitKey = isPanelCommitKey(event, scenario: scenario)

        try withModels(scenario: scenario, confirmsQuit: false) { keyModel, requestModel in
            let keyAction = keyModel.handleQuitKey(
                isRecordingShortcut: false,
                isPanelCommitKey: isCommitKey,
                isModalRunning: false
            )
            let reply = requestModel.handleTerminationRequest(
                isQuitKeyEvent: QuitConfirmation.isQuitKeyEvent(event),
                isQuitAppleEvent: false,
                isRecordingShortcut: false,
                isPanelCommitKey: isCommitKey,
                isModalRunning: false
            )

            #expect(keyAction == .quit)
            #expect(!keyModel.isConfirming)
            #expect(reply == .terminate)
            #expect(!requestModel.isConfirming)
        }
    }
}
