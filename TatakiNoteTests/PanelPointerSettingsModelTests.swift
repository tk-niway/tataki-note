import Testing
@testable import TatakiNote

@MainActor
struct PanelPointerSettingsModelTests {
    private func makeModel(
        move: Set<PanelPointerModifier> = [.command],
        resize: Set<PanelPointerModifier> = [.option]
    ) throws -> (PanelPointerSettingsModel, AppSettings, TemporaryDefaults) {
        let temp = try TemporaryDefaults()
        let settings = temp.makeSettings()
        settings.panelMoveModifiers = move
        settings.panelResizeModifiers = resize
        return (PanelPointerSettingsModel(settings: settings), settings, temp)
    }

    @Test("AC-2: チェックを入れる・外すと組み合わせが変わる")
    func checkingAndUncheckingChangesCombination() throws {
        let (model, settings, temp) = try makeModel()
        defer { temp.remove() }

        model.setModifier(.control, isOn: true, for: .move)
        #expect(settings.panelMoveModifiers == [.control, .command])
        #expect(model.isOn(.control, for: .move))
        #expect(model.rejectedAction == nil)

        model.setModifier(.control, isOn: false, for: .move)
        #expect(settings.panelMoveModifiers == [.command])
        #expect(!model.isOn(.control, for: .move))
    }

    @Test("AC-2: 全部外すと「使えない」の状態になる")
    func uncheckingAllMakesActionDisabled() throws {
        let (model, settings, temp) = try makeModel()
        defer { temp.remove() }

        #expect(!model.isDisabled(.move))
        model.setModifier(.command, isOn: false, for: .move)
        #expect(settings.panelMoveModifiers.isEmpty)
        #expect(model.isDisabled(.move))
        #expect(!model.isDisabled(.resize))
        #expect(model.rejectedAction == nil)
    }

    @Test("AC-2: もう一方と同じ組み合わせになるチェックは受け付けず、その行に理由が出る")
    func sameCombinationByCheckingIsRejected() throws {
        let (model, settings, temp) = try makeModel(move: [])
        defer { temp.remove() }

        model.setModifier(.option, isOn: true, for: .move)
        #expect(settings.panelMoveModifiers.isEmpty)
        #expect(!model.isOn(.option, for: .move))
        #expect(model.rejectedAction == .move)
        #expect(model.rejectionCount == 1)
        #expect(model.rejectionMessage(for: .move) == "サイズ変更と同じ組み合わせは選べません")
        #expect(model.rejectionMessage(for: .resize) == nil)
    }

    @Test("AC-2: もう一方と同じ組み合わせになる外す操作も受け付けず、サイズ変更の行には移動と同じ組み合わせの理由が出る")
    func sameCombinationByUncheckingIsRejected() throws {
        let (model, settings, temp) = try makeModel(move: [.option, .command], resize: [.option])
        defer { temp.remove() }

        model.setModifier(.command, isOn: false, for: .move)
        #expect(settings.panelMoveModifiers == [.option, .command])
        #expect(model.rejectedAction == .move)

        model.setModifier(.command, isOn: true, for: .resize)
        #expect(settings.panelResizeModifiers == [.option])
        #expect(model.rejectedAction == .resize)
        #expect(model.rejectionCount == 2)
        #expect(model.rejectionMessage(for: .resize) == "移動と同じ組み合わせは選べません")
        #expect(model.rejectionMessage(for: .move) == nil)
    }

    @Test("AC-2: 続けて同じ行で拒むと回数が増える")
    func repeatedRejectionIncrementsCount() throws {
        let (model, _, temp) = try makeModel(move: [])
        defer { temp.remove() }

        model.setModifier(.option, isOn: true, for: .move)
        model.setModifier(.option, isOn: true, for: .move)
        #expect(model.rejectedAction == .move)
        #expect(model.rejectionCount == 2)
    }

    @Test("AC-2: 次に受け付けられる操作をすると理由が消える(どちらの行でも)")
    func acceptedOperationClearsRejection() throws {
        let (model, settings, temp) = try makeModel(move: [])
        defer { temp.remove() }

        model.setModifier(.option, isOn: true, for: .move)
        #expect(model.rejectedAction == .move)

        model.setModifier(.shift, isOn: true, for: .resize)
        #expect(settings.panelResizeModifiers == [.shift, .option])
        #expect(model.rejectedAction == nil)
        #expect(model.rejectionMessage(for: .move) == nil)

        model.setModifier(.option, isOn: true, for: .move)
        #expect(model.rejectedAction == nil)
        #expect(settings.panelMoveModifiers == [.option])
    }

    @Test("AC-2: 今と同じ値を入れても何も変わらず、理由は消える")
    func settingSameValueKeepsEverything() throws {
        let (model, settings, temp) = try makeModel(move: [])
        defer { temp.remove() }

        model.setModifier(.option, isOn: true, for: .move)
        #expect(model.rejectedAction == .move)

        model.setModifier(.option, isOn: true, for: .resize)
        #expect(settings.panelResizeModifiers == [.option])
        #expect(settings.panelMoveModifiers.isEmpty)
        #expect(model.rejectedAction == nil)
    }

    @Test("AC-2: 行の名前・注記・説明の文")
    func texts() {
        #expect(PanelPointerSettingsModel.title(for: .move) == "ウィンドウの移動")
        #expect(PanelPointerSettingsModel.title(for: .resize) == "ウィンドウのサイズ変更")
        #expect(PanelPointerSettingsModel.disabledText == "チェックが無いあいだは使えません")
        #expect(PanelPointerSettingsModel.groupFooter == "修飾キーを押したままカーソルを動かすと、パネルが動く・大きさが変わる")
    }

    @Test("AC-20: 説明文に「(クリックは要らない)」を含まない")
    func groupFooterHasNoClickNote() {
        #expect(!PanelPointerSettingsModel.groupFooter.contains("クリックは要らない"))
    }
}
