import AppKit
@testable import TatakiNote

/// 単体テスト用の `PanelController` を作る。指定しない部品は、本物のシステムに触れない偽物にする。
@MainActor
enum PanelControllerFactory {
    static func make(
        settings: AppSettings,
        model: PanelModel = PanelModel(),
        probe: FocusedElementProbing? = nil,
        inserter: TextInserting? = nil,
        permission: AccessibilityPermissionChecking? = nil,
        exposeWebContent: @escaping (InsertionTarget) -> Void = { _ in },
        locateTargetWindowFrame: @escaping (pid_t) -> CGRect? = { _ in nil },
        ownProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        library: DraftLibrary = DraftLibrary(store: .inMemory),
        saveAnimation: SaveAnimationModel = SaveAnimationModel(),
        animator: PanelFrameAnimating = AppKitPanelFrameAnimator(),
        shaker: PanelShaking = PanelShaker(),
        beep: @escaping () -> Void = {},
        hideApplication: @escaping () -> Void = {},
        makeTargetMonitor: ((PanelModel) -> InsertionTargetMonitor)? = nil,
        exportChooser: ExportDestinationChoosing? = nil,
        writeTextFile: @escaping (String, URL) throws -> Void = TextFileWriter.write,
        sharer: TextSharing? = nil,
        presentExportFailure: @escaping (String, NSWindow?, @escaping () -> Void) -> Void = { _, _, completion in completion() }
    ) -> PanelController {
        let probe = probe ?? FocusedElementProbeStub()
        return PanelController(
            model: model,
            settings: settings,
            targetTracker: FrontmostAppTracker(workspace: .shared, ownProcessIdentifier: -1),
            inserter: inserter ?? InserterStub(result: .inserted),
            permission: permission ?? PermissionStub(isTrusted: true),
            fieldProbe: probe,
            exposeWebContent: exposeWebContent,
            locateTargetWindowFrame: locateTargetWindowFrame,
            ownProcessIdentifier: ownProcessIdentifier,
            library: library,
            saveAnimation: saveAnimation,
            animator: animator,
            shaker: shaker,
            beep: beep,
            hideApplication: hideApplication,
            makeTargetMonitor: makeTargetMonitor
                ?? InsertionTargetMonitor.testFactory(probe: probe, ownProcessIdentifier: ownProcessIdentifier),
            exportChooser: exportChooser ?? ExportChooserSpy(),
            writeTextFile: writeTextFile,
            sharer: sharer ?? SharerSpy(),
            presentExportFailure: presentExportFailure
        )
    }
}

extension PanelController {
    /// サイドバーの開閉で窓の枠を変えている間か。
    var isAdjustingFrameForSidebar: Bool {
        get { sizeController.isAdjustingFrameForSidebar }
        set { sizeController.isAdjustingFrameForSidebar = newValue }
    }

    /// 終了の前の処理を、ふつうの終了として行う。
    func prepareForTermination() {
        prepareForTermination(reason: .normal, store: RelaunchDraftStore(directory: nil))
    }
}
