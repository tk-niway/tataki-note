import AppKit

/// 入力欄の上に重ねて、自前のカーソルだけを描く view。点滅の時計も持つ。
final class EditorCaretView: NSView {
    /// 描く矩形(この view の座標)。`nil` なら何も描かない。
    var caretRect: CGRect? {
        didSet {
            guard caretRect != oldValue else { return }
            invalidate(oldValue, caretRect)
        }
    }

    /// カーソルの色。
    var color: NSColor = .controlTextColor {
        didSet { invalidate(caretRect) }
    }

    /// カーソルの形。
    var shape: EditorCaretShape = .bar {
        didSet { invalidate(caretRect) }
    }

    /// 点滅の今の状態。
    private(set) var blink: EditorCaretBlink

    private var clock: Task<Void, Never>?
    private var generation = 0

    init(frame frameRect: NSRect, periods: EditorCaretBlink.Periods) {
        blink = EditorCaretBlink(periods: periods)
        super.init(frame: frameRect)
        autoresizingMask = [.width, .height]
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    /// 点滅に出来事を渡す。時計は、状態機械が返したとおりに掛け直す。
    func send(_ event: EditorCaretBlink.Event) {
        let phase = blink.phase
        switch blink.handle(event) {
        case .none:
            break
        case .cancel:
            stopClock()
        case .schedule(let interval):
            startClock(after: interval)
        }
        if blink.phase != phase {
            invalidate(caretRect)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard blink.phase == .on, let caretRect else { return }
        let fill = shape == .block ? color.withAlphaComponent(EditorCaretGeometry.blockFillAlpha) : color
        fill.setFill()
        caretRect.fill()
    }

    private func startClock(after interval: TimeInterval) {
        clock?.cancel()
        generation += 1
        let current = generation
        clock = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(interval))
            } catch {
                return
            }
            guard let self, self.generation == current else { return }
            self.send(.tick)
        }
    }

    private func stopClock() {
        clock?.cancel()
        clock = nil
        generation += 1
    }

    private func invalidate(_ rects: CGRect?...) {
        for rect in rects {
            guard let rect else { continue }
            setNeedsDisplay(rect.insetBy(dx: -1, dy: -1))
        }
    }
}
