import CoreGraphics

/// カーソルの1回の動き・修飾キーの変化で読んだ値。
struct PanelPointerSample: Equatable {
    var pointer: CGPoint
    var modifiers: Set<PanelPointerModifier>
    var isMouseButtonPressed: Bool
}

/// パネルの今の状況。
struct PanelPointerAvailability: Equatable {
    var isPanelShown: Bool
    var isSidebarSliding: Bool
    var isSidebarOpen: Bool

    /// パネルの表示・動きの段階・サイドバーから状況を作る。
    static func make(
        isPresented: Bool,
        motionPhase: PanelMotionPhase,
        isSidebarSliding: Bool,
        isSidebarOpen: Bool
    ) -> PanelPointerAvailability {
        PanelPointerAvailability(
            isPanelShown: isPresented && motionPhase == .shown,
            isSidebarSliding: isSidebarSliding,
            isSidebarOpen: isSidebarOpen
        )
    }
}

/// そのときのパネルと設定。
struct PanelPointerContext: Equatable {
    var panelFrame: CGRect
    var isPanelShown: Bool
    var isSidebarSliding: Bool
    var isSidebarOpen: Bool
    var moveModifiers: Set<PanelPointerModifier>
    var resizeModifiers: Set<PanelPointerModifier>
    var screenTopLimit: CGFloat?
}

/// サイズ変更で動かす角。
enum PanelResizeCorner: Equatable {
    case topLeft, topRight, bottomLeft, bottomRight

    /// 枠を上下左右に4つに分けたとき、点のある区画の角。
    static func nearest(to point: CGPoint, in frame: CGRect) -> PanelResizeCorner {
        let isLeft = point.x < frame.midX
        let isTop = point.y >= frame.midY
        switch (isLeft, isTop) {
        case (true, true): return .topLeft
        case (false, true): return .topRight
        case (true, false): return .bottomLeft
        case (false, false): return .bottomRight
        }
    }
}

/// 始めたときの枠とカーソル。
struct PanelPointerAnchor: Equatable {
    var frame: CGRect
    var pointer: CGPoint
    var isSidebarOpen: Bool
}

/// 1回の処理で、呼び出し側がすること。
enum PanelPointerStep: Equatable {
    case none
    case begin(PanelPointerAction)
    case setOrigin(CGPoint)
    case setFrame(CGRect)

    /// 計算した枠を今の枠に当てるときの手順。同じなら none、大きさが同じなら setOrigin、違えば setFrame。
    static func applying(_ frame: CGRect, to currentFrame: CGRect) -> PanelPointerStep {
        if frame == currentFrame { return .none }
        if frame.size == currentFrame.size { return .setOrigin(frame.origin) }
        return .setFrame(frame)
    }
}

/// 修飾キーを押したままのカーソルの動きを、パネルの移動・サイズ変更にする。
struct PanelPointerGesture: Equatable {
    enum State: Equatable {
        case idle
        case moving(PanelPointerAnchor)
        case resizing(PanelPointerAnchor, PanelResizeCorner)
    }

    private(set) var state: State = .idle

    /// サンプルを受け取り、することを返す。
    mutating func handle(_ sample: PanelPointerSample, in context: PanelPointerContext) -> PanelPointerStep {
        let anchor: PanelPointerAnchor
        let action: PanelPointerAction
        switch state {
        case .idle:
            guard let started = Self.startingAction(for: sample, in: context) else { return .none }
            return .begin(started)
        case .moving(let movingAnchor):
            anchor = movingAnchor
            action = .move
        case .resizing(let resizingAnchor, _):
            anchor = resizingAnchor
            action = .resize
        }

        let modifiers = action == .move ? context.moveModifiers : context.resizeModifiers
        if sample.isMouseButtonPressed
            || modifiers.isEmpty
            || sample.modifiers != modifiers
            || !context.isPanelShown {
            return stopAndRestart(sample, in: context)
        }
        if context.isSidebarSliding { return .none }

        if context.isSidebarOpen != anchor.isSidebarOpen {
            let renewed = PanelPointerAnchor(
                frame: context.panelFrame,
                pointer: sample.pointer,
                isSidebarOpen: context.isSidebarOpen
            )
            switch state {
            case .moving: state = .moving(renewed)
            case .resizing(_, let corner): state = .resizing(renewed, corner)
            case .idle: break
            }
            return .none
        }

        switch state {
        case .idle:
            return .none
        case .moving:
            let frame = PanelPointerFrame.moved(
                anchor: anchor,
                pointer: sample.pointer,
                screenTopLimit: context.screenTopLimit
            )
            return PanelPointerStep.applying(frame, to: context.panelFrame)
        case .resizing(_, let corner):
            let frame = PanelPointerFrame.resized(
                anchor: anchor,
                corner: corner,
                pointer: sample.pointer,
                minimumSize: SidebarLayout.minimumWindowSize(isSidebarOpen: context.isSidebarOpen),
                screenTopLimit: context.screenTopLimit
            )
            return PanelPointerStep.applying(frame, to: context.panelFrame)
        }
    }

    /// 起点を置いて始める。resize なら角をカーソルの位置から決める。
    mutating func begin(_ action: PanelPointerAction, pointer: CGPoint, frame: CGRect, isSidebarOpen: Bool) {
        let anchor = PanelPointerAnchor(frame: frame, pointer: pointer, isSidebarOpen: isSidebarOpen)
        switch action {
        case .move:
            state = .moving(anchor)
        case .resize:
            state = .resizing(anchor, PanelResizeCorner.nearest(to: pointer, in: frame))
        }
    }

    /// 止める(idle に戻す)。
    mutating func reset() {
        state = .idle
    }

    /// 始める操作。始めないなら nil。
    static func startingAction(for sample: PanelPointerSample, in context: PanelPointerContext) -> PanelPointerAction? {
        guard !sample.isMouseButtonPressed,
              context.isPanelShown,
              !context.isSidebarSliding,
              context.panelFrame.contains(sample.pointer)
        else { return nil }
        if !context.moveModifiers.isEmpty, sample.modifiers == context.moveModifiers { return .move }
        if !context.resizeModifiers.isEmpty, sample.modifiers == context.resizeModifiers { return .resize }
        return nil
    }

    private mutating func stopAndRestart(
        _ sample: PanelPointerSample,
        in context: PanelPointerContext
    ) -> PanelPointerStep {
        state = .idle
        guard let action = Self.startingAction(for: sample, in: context) else { return .none }
        return .begin(action)
    }
}

/// 移動・サイズ変更の枠の計算。
enum PanelPointerFrame {
    /// 起点の枠をカーソルの動きの分だけ動かす。上端は限度を越えない。
    static func moved(anchor: PanelPointerAnchor, pointer: CGPoint, screenTopLimit: CGFloat?) -> CGRect {
        let dx = pointer.x - anchor.pointer.x
        let dy = pointer.y - anchor.pointer.y
        var frame = anchor.frame.offsetBy(dx: dx, dy: dy)
        if let limit = topLimit(screenTopLimit: screenTopLimit, anchorFrame: anchor.frame), frame.maxY > limit {
            frame.origin.y = limit - frame.height
        }
        return frame
    }

    /// 角をカーソルの動きの分だけ動かし、反対の角を止める。最小の大きさで止まる。上端は限度を越えない。
    static func resized(
        anchor: PanelPointerAnchor,
        corner: PanelResizeCorner,
        pointer: CGPoint,
        minimumSize: CGSize,
        screenTopLimit: CGFloat?
    ) -> CGRect {
        let dx = pointer.x - anchor.pointer.x
        let dy = pointer.y - anchor.pointer.y
        let base = anchor.frame
        var frame = base

        switch corner {
        case .topRight, .bottomRight:
            frame.size.width = max(base.width + dx, minimumSize.width)
            frame.origin.x = base.minX
        case .topLeft, .bottomLeft:
            frame.size.width = max(base.width - dx, minimumSize.width)
            frame.origin.x = base.maxX - frame.size.width
        }

        switch corner {
        case .topLeft, .topRight:
            var top = base.maxY + dy
            if let limit = topLimit(screenTopLimit: screenTopLimit, anchorFrame: base) {
                top = min(top, limit)
            }
            frame.size.height = max(top - base.minY, minimumSize.height)
            frame.origin.y = base.minY
        case .bottomLeft, .bottomRight:
            frame.size.height = max(base.height - dy, minimumSize.height)
            frame.origin.y = base.maxY - frame.size.height
        }
        return frame
    }

    /// 上端の限度。画面の上端と起点の上端の高い方。画面が無ければ nil。
    static func topLimit(screenTopLimit: CGFloat?, anchorFrame: CGRect) -> CGFloat? {
        guard let screenTopLimit else { return nil }
        return max(screenTopLimit, anchorFrame.maxY)
    }

    /// 点のある画面の使える範囲の上端。どの画面にも無ければ nil。
    static func screenTopLimit(at point: CGPoint, screens: [(frame: CGRect, visibleFrame: CGRect)]) -> CGFloat? {
        if let screen = screens.first(where: { $0.frame.contains(point) }) {
            return screen.visibleFrame.maxY
        }
        let closed = screens.first { screen in
            (screen.frame.minX...screen.frame.maxX).contains(point.x)
                && (screen.frame.minY...screen.frame.maxY).contains(point.y)
        }
        return closed?.visibleFrame.maxY
    }
}
