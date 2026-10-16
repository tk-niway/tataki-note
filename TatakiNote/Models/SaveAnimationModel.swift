import Foundation
import Observation
import SwiftUI

/// 保存した本文の写しが飛び込む先。
enum SaveFlightDestination: Hashable {
    case sidebarToggle
    case draftRow(UUID)
    case draftsTab
}

extension SaveFlightDestination {
    /// サイドバーが閉じていれば開閉ボタン、開いて下書きを出していて保存した下書きの行が一覧に出ていればその行、それ以外は「下書き」の切り替え。
    static func resolve(
        savedDraftID: UUID,
        isSidebarOpen: Bool,
        isShowingDrafts: Bool,
        visibleDraftIDs: [UUID]
    ) -> SaveFlightDestination {
        guard isSidebarOpen else { return .sidebarToggle }
        if isShowingDrafts, visibleDraftIDs.contains(savedDraftID) {
            return .draftRow(savedDraftID)
        }
        return .draftsTab
    }

    /// 保存の前にサイドバーを下書きに切り替えるか。保存で、サイドバーが開いて履歴を出しているときだけ。
    static func shouldSwitchToDrafts(isSidebarOpen: Bool, tab: SidebarTab) -> Bool {
        isSidebarOpen && tab == .history
    }
}

/// 1 回の保存の演出。
struct SaveFlight: Equatable {
    let id: Int
    let text: String
    let destination: SaveFlightDestination
}

/// 保存の演出の段。
enum SaveAnimationPhase: Equatable {
    case idle
    case flying(SaveFlight)
    case arrived(SaveFlight)
}

/// 着いた所に散らす粒の置き方。
enum SaveBurst {
    static let particleCount = 14
    static let minimumDistance: CGFloat = 22
    static let maximumDistance: CGFloat = 52

    /// i 番目の粒の向き(ラジアン)と飛ぶ距離(22〜52pt)。
    static func particle(at index: Int) -> (angle: Double, distance: CGFloat) {
        let angle = Double(index) / Double(particleCount) * 2 * .pi
        let step = (index * 5) % particleCount
        let fraction = CGFloat(step) / CGFloat(particleCount - 1)
        return (angle, minimumDistance + (maximumDistance - minimumDistance) * fraction)
    }
}

extension Duration {
    /// 秒数。
    var seconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) * 1e-18
    }
}

/// 保存の演出の進み方。
@Observable final class SaveAnimationModel {
    static let flyingDuration: Duration = .milliseconds(680)
    static let arrivalDuration: Duration = .milliseconds(720)
    static let toastDuration: Duration = .milliseconds(1900)
    static let savedMessage = "下書きに保存しました"

    private(set) var phase: SaveAnimationPhase = .idle
    /// 着いたときに 1 つ進む。着いた所が弾むきっかけ。
    private(set) var arrivalCount = 0
    /// 着いて光っている下書きの行。
    private(set) var glowingDraftID: UUID?
    /// パネルの中に出しているトーストの文。出していなければ nil。
    private(set) var toastMessage: String?
    private(set) var playCount = 0

    @ObservationIgnored private let sleep: (Duration) async -> Void
    @ObservationIgnored private let announce: (String) -> Void

    init(
        sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        announce: @escaping (String) -> Void = { AccessibilityNotification.Announcement($0).post() }
    ) {
        self.sleep = sleep
        self.announce = announce
    }

    /// 本文の写しを destination へ飛ばし、着いたら弾ませてトーストを出す。新しい保存が来たら前の演出を打ち切る。
    func play(text: String, destination: SaveFlightDestination) async {
        playCount += 1
        let generation = playCount
        glowingDraftID = nil
        toastMessage = nil
        let flight = SaveFlight(id: generation, text: text, destination: destination)
        phase = .flying(flight)
        await sleep(Self.flyingDuration)
        guard generation == playCount else { return }
        phase = .arrived(flight)
        arrivalCount += 1
        if case .draftRow(let id) = destination {
            glowingDraftID = id
        }
        toastMessage = Self.savedMessage
        announce(Self.savedMessage)
        await sleep(Self.arrivalDuration)
        guard generation == playCount else { return }
        phase = .idle
        glowingDraftID = nil
        await sleep(Self.toastDuration - Self.arrivalDuration)
        guard generation == playCount else { return }
        toastMessage = nil
    }

    /// 演出とトーストをすぐ止める。
    func cancel() {
        playCount += 1
        phase = .idle
        glowingDraftID = nil
        toastMessage = nil
    }
}
