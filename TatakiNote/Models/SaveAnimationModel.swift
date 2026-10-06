import Foundation
import Observation
import SwiftUI

/// 保存のアニメーションの段。
enum SaveAnimationPhase: Equatable {
    case idle
    case flying
    case absorbing
}

extension Duration {
    /// 秒数。
    var seconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) * 1e-18
    }
}

/// 保存のアニメーションの進み方。
@Observable final class SaveAnimationModel {
    static let flyingDuration: Duration = .milliseconds(500)
    static let absorbingDuration: Duration = .milliseconds(250)
    static let highlightDuration: Duration = .milliseconds(700)
    static let saveConfirmationDuration: Duration = .milliseconds(700)
    static let maximumTotal: Duration = .milliseconds(800)

    static let savedAnnouncement = "保存しました"

    private(set) var phase: SaveAnimationPhase = .idle
    private(set) var highlightedDraftID: UUID?
    private(set) var isShowingSaveConfirmation = false
    private(set) var playCount = 0
    private(set) var absorbCount = 0

    @ObservationIgnored private let sleep: (Duration) async -> Void
    @ObservationIgnored private let announce: (String) -> Void

    init(
        sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        announce: @escaping (String) -> Void = { AccessibilityNotification.Announcement($0).post() }
    ) {
        self.sleep = sleep
        self.announce = announce
    }

    /// 保存の知らせに合わせて動きを進める。新しい知らせが来たら前の動きは打ち切る。
    func play(_ event: DraftSaveEvent, isSidebarOpen: Bool) async {
        playCount += 1
        let generation = playCount
        reset()
        switch event.kind {
        case .created(let id):
            if isSidebarOpen {
                highlightedDraftID = id
                await sleep(Self.highlightDuration)
                guard generation == playCount else { return }
                highlightedDraftID = nil
            } else {
                phase = .flying
                await sleep(Self.flyingDuration)
                guard generation == playCount else { return }
                phase = .absorbing
                absorbCount += 1
                await sleep(Self.absorbingDuration)
                guard generation == playCount else { return }
                phase = .idle
            }
        case .overwritten:
            isShowingSaveConfirmation = true
            announce(Self.savedAnnouncement)
            await sleep(Self.saveConfirmationDuration)
            guard generation == playCount else { return }
            isShowingSaveConfirmation = false
        }
    }

    private func reset() {
        phase = .idle
        highlightedDraftID = nil
        isShowingSaveConfirmation = false
    }
}
