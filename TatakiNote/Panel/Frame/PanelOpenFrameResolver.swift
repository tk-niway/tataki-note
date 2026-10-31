import AppKit

/// パネルを開くときの窓の枠を決める。
struct PanelOpenFrameResolver {
    let fieldProbe: FocusedElementProbing
    let locateTargetWindowFrame: (pid_t) -> CGRect?
    let ownProcessIdentifier: pid_t
    var primaryScreenFrame: () -> CGRect? = { ScreenCoordinates.primaryScreenFrame }
    var screens: () -> [ScreenGeometry] = {
        NSScreen.screens.map { ScreenGeometry(frame: $0.frame, visibleFrame: $0.visibleFrame) }
    }
    var mouseLocation: () -> CGPoint = { NSEvent.mouseLocation }

    /// 挿入先のアプリへアクセシビリティの問い合わせをしてよいか。自分自身が挿入先のときは問い合わせない。
    static func shouldQueryAccessibility(of target: InsertionTarget?, ownProcessIdentifier: pid_t) -> Bool {
        guard let target else { return false }
        return !target.isOwnApp(ownProcessIdentifier)
    }

    /// パネルを開くときに、挿入先へ Web の中身を出すよう頼むか。
    static func shouldExposeWebContent(target: InsertionTarget?, ownProcessIdentifier: pid_t, isTrusted: Bool) -> Bool {
        shouldQueryAccessibility(of: target, ownProcessIdentifier: ownProcessIdentifier) && isTrusted
    }

    /// 挿入先のウィンドウの枠を求めるクロージャ。挿入先が無ければ一覧を取らずに `nil` を返す。
    static func windowFrameLocator(
        for target: InsertionTarget?,
        locate: @escaping (pid_t) -> CGRect?
    ) -> () -> CGRect? {
        { target.flatMap { locate($0.processIdentifier) } }
    }

    /// 開くときの窓の枠。出す画面が決まらなければ `nil`(呼び出し側が真ん中に置く)。
    /// `queriesField` が false のときは、入力欄の位置を挿入先のアプリへ問い合わせない。
    func frame(
        target: InsertionTarget?,
        mode: PanelScreen,
        isTrusted: Bool,
        observedFocus: ObservedFocus?,
        queriesField: Bool = true,
        isSidebarOpen: Bool,
        openingSize: (CGRect) -> CGSize
    ) -> NSRect? {
        let queriesAccessibility = Self.shouldQueryAccessibility(
            of: target,
            ownProcessIdentifier: ownProcessIdentifier
        )
        let fieldFrame = primaryScreenFrame().flatMap { primaryScreenFrame in
            PanelOpenPlacement.fieldFrame(
                mode: mode,
                isTrusted: isTrusted,
                target: queriesAccessibility ? target : nil,
                probe: fieldProbe,
                observedFocus: observedFocus,
                primaryScreenHeight: primaryScreenFrame.height,
                queriesMissingFrame: queriesField
            )
        }
        let currentScreens = screens()
        let currentMouseLocation = mouseLocation()
        guard let screen = PanelOpenPlacement.screen(
            mode: mode,
            screens: currentScreens,
            mouseLocation: currentMouseLocation,
            fieldFrame: fieldFrame,
            locateTargetWindowFrame: Self.windowFrameLocator(for: target, locate: locateTargetWindowFrame)
        ) else { return nil }
        let placed = PanelOpenPlacement.frame(
            size: openingSize(screen.visibleFrame),
            on: screen,
            mode: mode,
            fieldFrame: fieldFrame,
            mouseLocation: currentMouseLocation
        )
        return isSidebarOpen
            ? SidebarLayout.expandedFrame(bodyFrame: placed, visibleFrame: screen.visibleFrame)
            : placed
    }
}
