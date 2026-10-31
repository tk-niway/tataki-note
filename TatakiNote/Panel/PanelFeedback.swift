import AppKit
import Foundation

/// パネルでの知らせ。空のときの揺れ・ビープ、トースト、保存の動き。
final class PanelFeedback {
    private let panel: NSWindow
    private let model: PanelModel
    private let session: DraftSession
    private let sidebarModel: SidebarModel
    private let library: DraftLibrary
    private let saveAnimation: SaveAnimationModel
    private let settings: AppSettings
    private let shaker: PanelShaking
    private let beep: () -> Void

    init(
        panel: NSWindow,
        model: PanelModel,
        session: DraftSession,
        sidebarModel: SidebarModel,
        library: DraftLibrary,
        saveAnimation: SaveAnimationModel,
        settings: AppSettings,
        shaker: PanelShaking,
        beep: @escaping () -> Void
    ) {
        self.panel = panel
        self.model = model
        self.session = session
        self.sidebarModel = sidebarModel
        self.library = library
        self.saveAnimation = saveAnimation
        self.settings = settings
        self.shaker = shaker
        self.beep = beep
    }

    /// 下書きの保存と、書きかけを履歴へ移したことを見張り、パネルが開いていれば保存の動き・トーストを出す。
    func startObserving() {
        observeSaveEvents()
        observeArchivedScratch()
    }

    /// 入力が空で操作できないことを、動きの段階とアニメーションの設定に応じて揺れかビープで知らせる。
    func signalEmptyInput(motionPhase: PanelMotionPhase) {
        switch PanelShake.emptyInputFeedback(motionPhase: motionPhase, isAnimationEnabled: settings.isAnimationEnabled) {
        case .shake:
            shaker.shake(panel)
        case .beep:
            beep()
        case .none:
            break
        }
    }

    /// トーストを出す。
    func showToast(_ message: String, style: PanelToastStyle = .done) {
        let animation = saveAnimation
        Task { await animation.showToast(message, style: style) }
    }

    /// 揺れを止める。
    func stopShaking() {
        shaker.stop(panel)
    }

    /// 揺れを止め、保存の動きを取り消す。
    func stopEffects() {
        stopShaking()
        saveAnimation.cancel()
    }

    private func observeSaveEvents() {
        observeRepeatedly(
            tracking: { [weak self] in _ = self?.session.lastSaveEvent },
            onChange: { [weak self] in
                guard let self else { return false }
                if let event = self.session.lastSaveEvent {
                    self.playSaveAnimation(for: event)
                }
                return true
            }
        )
    }

    private func playSaveAnimation(for event: DraftSaveEvent) {
        guard model.isPresented else { return }
        let id: UUID
        switch event.kind {
        case .created(let savedID), .overwritten(let savedID):
            id = savedID
        }
        if SaveFlightDestination.shouldSwitchToDrafts(
            isSidebarOpen: sidebarModel.isOpen,
            tab: sidebarModel.tab
        ) {
            sidebarModel.tab = .drafts
        }
        let text = library.draft(id: id)?.text ?? model.text
        let destination = SaveFlightDestination.resolve(
            savedDraftID: id,
            isSidebarOpen: sidebarModel.isOpen,
            isShowingDrafts: sidebarModel.tab == .drafts,
            visibleDraftIDs: sidebarModel.rows.map(\.id)
        )
        let animation = saveAnimation
        let showsToast = event.showsToast
        let isAnimated = settings.isAnimationEnabled
        Task {
            await animation.play(text: text, destination: destination, showsToast: showsToast, isAnimated: isAnimated)
        }
    }

    private func observeArchivedScratch() {
        observeRepeatedly(
            tracking: { [weak self] in _ = self?.session.archivedScratchCount },
            onChange: { [weak self] in
                guard let self else { return false }
                self.showArchivedToast()
                return true
            }
        )
    }

    private func showArchivedToast() {
        guard model.isPresented else { return }
        showToast(SaveAnimationModel.archivedMessage)
    }
}
