import CoreGraphics

/// @note p0-364
enum PanelOpenPlacement {
    /// @note p0-365
    static let fieldGap: CGFloat = 8

    /// @note p0-366
    static func fieldFrame(
        mode: PanelScreen,
        isTrusted: Bool,
        target: InsertionTarget?,
        probe: FocusedElementProbing,
        primaryScreenHeight: CGFloat
    ) -> CGRect? {
        guard mode == .nearFocusedField, isTrusted, let target else { return nil }
        let focused = probe.probeFocusedElement(in: target, readsFrame: true)
        guard FocusedTextInputState.classify(focused.lookup) == .textInput, let frame = focused.frame else { return nil }
        return PanelPlacement.cocoaFrame(fromQuartz: frame, primaryScreenHeight: primaryScreenHeight)
    }

    /// @note p0-367
    static func screen(
        mode: PanelScreen,
        screens: [ScreenGeometry],
        mouseLocation: CGPoint,
        targetWindowFrame: CGRect?,
        fieldFrame: CGRect?
    ) -> ScreenGeometry? {
        if mode == .nearFocusedField, let fieldFrame,
           let screen = PanelPlacement.screenWithLargestOverlap(with: fieldFrame, in: screens) {
            return screen
        }
        return PanelPlacement.screen(
            for: mode,
            screens: screens,
            mouseLocation: mouseLocation,
            targetWindowFrame: targetWindowFrame
        )
    }

    /// @note p0-368
    static func frame(size: CGSize, on screen: ScreenGeometry, mode: PanelScreen, fieldFrame: CGRect?) -> CGRect {
        let visibleFrame = screen.visibleFrame
        let fittedSize = CGSize(width: min(size.width, visibleFrame.width), height: min(size.height, visibleFrame.height))
        if mode == .nearFocusedField, let fieldFrame,
           PanelPlacement.screenWithLargestOverlap(with: fieldFrame, in: [screen]) != nil {
            return nearField(size: fittedSize, fieldFrame: fieldFrame, visibleFrame: visibleFrame)
        }
        return PanelPlacement.centeredFrame(size: fittedSize, in: visibleFrame)
    }

    /// @note p0-369
    static func nearField(size: CGSize, fieldFrame: CGRect, visibleFrame: CGRect) -> CGRect {
        let x = min(max(fieldFrame.minX, visibleFrame.minX), visibleFrame.maxX - size.width).rounded()

        let belowY = fieldFrame.minY - fieldGap - size.height
        if fits(y: belowY, height: size.height, in: visibleFrame) {
            return CGRect(x: x, y: belowY.rounded(), width: size.width, height: size.height)
        }

        let aboveY = fieldFrame.maxY + fieldGap
        if fits(y: aboveY, height: size.height, in: visibleFrame) {
            return CGRect(x: x, y: aboveY.rounded(), width: size.width, height: size.height)
        }

        return PanelPlacement.centeredFrame(size: size, in: visibleFrame)
    }

    /// @note p0-370
    private static func fits(y: CGFloat, height: CGFloat, in visibleFrame: CGRect) -> Bool {
        y >= visibleFrame.minY && y + height <= visibleFrame.maxY
    }
}
