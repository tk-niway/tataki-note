import AppKit

/// パネルの窓を揺らす。
protocol PanelShaking: AnyObject {
    /// 窓を横に揺らして元の位置に戻す。揺れている途中なら元の位置から始め直す。
    func shake(_ window: NSWindow)
    /// 揺れを止めて、窓を揺れる前の位置に戻す。揺れていなければ何もしない。
    func stop(_ window: NSWindow)
}

/// `setFrameOrigin` で窓を 1 歩ずつ動かして揺らす。
final class PanelShaker: PanelShaking {
    private let sleep: (Duration) async -> Void
    private var generation = 0
    private var restOrigin: CGPoint?
    private var lastPlacedOrigin: CGPoint = .zero

    init(sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    func shake(_ window: NSWindow) {
        let rest = restOrigin ?? window.frame.origin
        if restOrigin != nil {
            window.setFrameOrigin(rest)
        }
        restOrigin = rest
        lastPlacedOrigin = rest
        generation += 1
        let token = generation
        let sleep = self.sleep
        Task { [weak self, weak window] in
            for offset in PanelShake.offsets {
                await sleep(PanelShake.stepDuration)
                guard let self, self.generation == token else { return }
                guard let window else {
                    self.restOrigin = nil
                    return
                }
                guard PanelShake.shouldContinue(currentOrigin: window.frame.origin, lastPlacedOrigin: self.lastPlacedOrigin) else {
                    self.restOrigin = nil
                    return
                }
                let origin = CGPoint(x: rest.x + offset, y: rest.y)
                window.setFrameOrigin(origin)
                self.lastPlacedOrigin = origin
            }
            self?.restOrigin = nil
        }
    }

    func stop(_ window: NSWindow) {
        guard let rest = restOrigin else { return }
        generation += 1
        restOrigin = nil
        window.setFrameOrigin(rest)
    }
}
