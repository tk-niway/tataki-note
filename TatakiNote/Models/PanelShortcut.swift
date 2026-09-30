import AppKit

/// @note p0-383
struct PanelShortcut: Hashable {
    /// @note p0-384
    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    let keyCode: UInt16
    /// @note p0-385
    let modifiers: NSEvent.ModifierFlags

    /// @note p0-386
    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode == KeyCode.keypadEnter ? KeyCode.returnKey : keyCode
        self.modifiers = modifiers.intersection(Self.relevantModifiers)
    }

    /// @note p0-387
    static let shiftReturn = PanelShortcut(keyCode: KeyCode.returnKey, modifiers: [.shift])
    /// @note p0-388
    static let commandReturn = PanelShortcut(keyCode: KeyCode.returnKey, modifiers: [.command])
    /// @note p0-389
    static let commandShiftReturn = PanelShortcut(keyCode: KeyCode.returnKey, modifiers: [.command, .shift])

    /// @note p0-390
    static let defaultCommitKey: PanelShortcut? = nil
    static let defaultCommitAndSendKey: PanelShortcut? = .commandReturn
    /// @note p0-391
    static let legacyDefaultCommitKey: PanelShortcut? = .commandReturn
    static let legacyDefaultCommitAndSendKey: PanelShortcut? = nil

    /// @note p0-392
    var hasModifier: Bool {
        !modifiers.isEmpty
    }

    /// @note p0-393
    func matches(_ input: PanelKeyInput) -> Bool {
        let normalizedKeyCode = input.keyCode == KeyCode.keypadEnter ? KeyCode.returnKey : input.keyCode
        let normalizedModifiers = input.modifiers.intersection(Self.relevantModifiers)
        return normalizedKeyCode == keyCode && normalizedModifiers == modifiers
    }

    /// @note p0-394
    var storedValue: [Int] {
        [Int(keyCode), Int(modifiers.rawValue)]
    }

    /// @note p0-395
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
