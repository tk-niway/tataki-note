import CoreGraphics
@testable import TatakiNote

@MainActor
extension DraftSession {
    /// 終了の前の処理を、ふつうの終了として行う。
    func prepareForTermination() {
        prepareForTermination(reason: .normal, store: RelaunchDraftStore(directory: nil))
    }
}

@MainActor
extension PanelOpenPlacement {
    /// 挿入先のウィンドウの枠を値で渡して、出す画面を選ぶ。
    static func screen(
        mode: PanelScreen,
        screens: [ScreenGeometry],
        mouseLocation: CGPoint,
        targetWindowFrame: CGRect?,
        fieldFrame: CGRect?
    ) -> ScreenGeometry? {
        screen(
            mode: mode,
            screens: screens,
            mouseLocation: mouseLocation,
            fieldFrame: fieldFrame,
            locateTargetWindowFrame: { targetWindowFrame }
        )
    }
}
