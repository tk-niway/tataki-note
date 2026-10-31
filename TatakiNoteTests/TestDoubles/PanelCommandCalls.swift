@testable import TatakiNote

extension PanelController {
    func closeFromButton() { perform(.close, from: .button) }
    func commitFromButton(shouldSendAfterInsert: Bool) { perform(shouldSendAfterInsert ? .commitAndSend : .commit, from: .button) }
    func newDraftFromButton() { perform(.newDraft, from: .button) }
    func saveDraftFromButton() { perform(.saveDraft, from: .button) }
    func shareFromButton() { perform(.share, from: .button) }
    func switchToInsertFromButton() { perform(.switchToInsert, from: .button) }
    func toggleSidebarFromButton() { perform(.toggleSidebar, from: .button) }
    func openSettings() { perform(.openSettings, from: .button) }
}

extension PanelView {
    init(model: PanelModel, settings: AppSettings, onKeyInput: @escaping (PanelKeyInput) -> Bool, onClose: @escaping () -> Void) {
        self.init(model: model, settings: settings, onKeyInput: onKeyInput, onCommand: { if $0 == .close { onClose() } })
    }
}
