import AppKit

/// パネルの確定・確定+送信に割り当てるキー(修飾キー付きの任意のキー)。
struct PanelShortcut: Hashable {
    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode == KeyCode.keypadEnter ? KeyCode.returnKey : keyCode
        self.modifiers = modifiers.intersection(Self.relevantModifiers)
    }

    static let shiftReturn = PanelShortcut(keyCode: KeyCode.returnKey, modifiers: [.shift])
    static let commandReturn = PanelShortcut(keyCode: KeyCode.returnKey, modifiers: [.command])
    static let commandShiftReturn = PanelShortcut(keyCode: KeyCode.returnKey, modifiers: [.command, .shift])

    static let defaultCommitKey: PanelShortcut? = .commandShiftReturn
    static let defaultCommitAndSendKey: PanelShortcut? = .commandReturn
    static let legacyDefaultCommitKey: PanelShortcut? = .commandReturn
    static let legacyDefaultCommitAndSendKey: PanelShortcut? = nil

    var hasModifier: Bool {
        !modifiers.isEmpty
    }

    func matches(_ input: PanelKeyInput) -> Bool {
        let normalizedKeyCode = input.keyCode == KeyCode.keypadEnter ? KeyCode.returnKey : input.keyCode
        let normalizedModifiers = input.modifiers.intersection(Self.relevantModifiers)
        return normalizedKeyCode == keyCode && normalizedModifiers == modifiers
    }

    var storedValue: [Int] {
        [Int(keyCode), Int(modifiers.rawValue)]
    }

    init?(storedValue: [Any]) {
        guard storedValue.count == 2,
              let keyNumber = storedValue[0] as? NSNumber, CFGetTypeID(keyNumber) != CFBooleanGetTypeID(),
              let modifiersNumber = storedValue[1] as? NSNumber, CFGetTypeID(modifiersNumber) != CFBooleanGetTypeID()
        else { return nil }

        guard let keyValue = Int(exactly: keyNumber.doubleValue), keyValue >= 0, keyValue <= Int(UInt16.max)
        else { return nil }

        guard let modifiersValue = Int(exactly: modifiersNumber.doubleValue), let rawModifiers = UInt(exactly: modifiersValue)
        else { return nil }

        let modifiers = NSEvent.ModifierFlags(rawValue: rawModifiers)
        guard !modifiers.intersection(Self.relevantModifiers).isEmpty,
              modifiers.subtracting(Self.relevantModifiers).isEmpty
        else { return nil }

        self.init(keyCode: UInt16(keyValue), modifiers: modifiers)
    }

    static func == (lhs: PanelShortcut, rhs: PanelShortcut) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.modifiers.rawValue == rhs.modifiers.rawValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifiers.rawValue)
    }
}
