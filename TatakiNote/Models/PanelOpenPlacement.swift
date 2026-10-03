import CoreGraphics

/// 閉じた状態からパネルを開くときの枠の決め方(「入力欄の近く」を含む)。
enum PanelOpenPlacement {
    static let fieldGap: CGFloat = 8

    /// 「入力欄の近く」で使う入力欄の枠(Cocoa の座標)。入力欄の位置が使えなければ `nil`。
    static func fieldFrame(
        mode: PanelScreen,
        isTrusted: Bool,
        target: InsertionTarget?,
        probe: FocusedElementProbing,
        observedFocus: ObservedFocus? = nil,
        primaryScreenHeight: CGFloat
    ) -> CGRect? {
        guard mode == .nearFocusedField, isTrusted, let target else { return nil }
        let frame: CGRect?
        if let observedFocus, observedFocus.processIdentifier == target.processIdentifier {
            guard FocusedTextInputState.classify(observedFocus.probe.lookup) == .textInput else { return nil }
            frame = observedFocus.probe.frame ?? observedFocus.probe.element.flatMap { probe.frame(of: $0) }
        } else {
            let focused = probe.probeFocusedElement(in: target, readsFrame: true)
            guard FocusedTextInputState.classify(focused.lookup) == .textInput else { return nil }
            frame = focused.frame
        }
        guard let frame else { return nil }
        return PanelPlacement.cocoaFrame(fromQuartz: frame, primaryScreenHeight: primaryScreenHeight)
    }

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

    /// 出す画面を選ぶ。挿入先のウィンドウの枠は、画面の決定に要るときだけ求める。
    static func screen(
        mode: PanelScreen,
        screens: [ScreenGeometry],
        mouseLocation: CGPoint,
        fieldFrame: CGRect?,
        locateTargetWindowFrame: () -> CGRect?
    ) -> ScreenGeometry? {
        if mode == .nearFocusedField, let fieldFrame,
           let screen = PanelPlacement.screenWithLargestOverlap(with: fieldFrame, in: screens) {
            return screen
        }
        return PanelPlacement.screen(
            for: mode,
            screens: screens,
            mouseLocation: mouseLocation,
            targetWindowFrame: mode.usesTargetWindowFrame ? locateTargetWindowFrame() : nil
        )
    }

    static func frame(size: CGSize, on screen: ScreenGeometry, mode: PanelScreen, fieldFrame: CGRect?) -> CGRect {
        let visibleFrame = screen.visibleFrame
        let fittedSize = PanelPlacement.fittedSize(size, in: visibleFrame)
        if mode == .nearFocusedField, let fieldFrame,
           PanelPlacement.screenWithLargestOverlap(with: fieldFrame, in: [screen]) != nil {
            return nearField(size: fittedSize, fieldFrame: fieldFrame, visibleFrame: visibleFrame)
        }
        return PanelPlacement.centeredFrame(size: fittedSize, in: visibleFrame)
    }

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

    private static func fits(y: CGFloat, height: CGFloat, in visibleFrame: CGRect) -> Bool {
        y >= visibleFrame.minY && y + height <= visibleFrame.maxY
    }
}
