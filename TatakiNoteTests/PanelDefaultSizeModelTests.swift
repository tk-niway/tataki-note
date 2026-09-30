import CoreGraphics
import Foundation
import Observation
import os
import Testing
@testable import TatakiNote

/// @note p0-907
@MainActor
@Observable final class HeldPanelSizeSource {
    var size: CGSize?
}

@MainActor
struct PanelDefaultSizeModelTests {
    /// @note p0-908
    private func makeSettings(suite name: String) throws -> AppSettings {
        let defaults = try #require(UserDefaults(suiteName: name))
        return AppSettings(store: SettingsStore(defaults: defaults))
    }

    /// @note p0-909
    private func makeModel(suite name: String, source: HeldPanelSizeSource? = nil) throws -> PanelDefaultSizeModel {
        let source = source ?? HeldPanelSizeSource()
        return PanelDefaultSizeModel(settings: try makeSettings(suite: name), currentPanelSize: { source.size })
    }

    private func removeSuite(_ name: String) {
        UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
    }

    /// @note p0-910
    private func countCanUseChanges(of model: PanelDefaultSizeModel) -> OSAllocatedUnfairLock<Int> {
        let changes = OSAllocatedUnfairLock(initialState: 0)
        withObservationTracking {
            _ = model.canUseCurrentPanelSize
        } onChange: {
            changes.withLock { $0 += 1 }
        }
        return changes
    }

    // MARK: - 幅と高さ

    @Test("AC-13: 初期値は 520×340、ステッパーの範囲は幅 320〜4000・高さ 160〜4000 で 1段 10、変えた値は起動し直しても残る")
    func widthAndHeightAreSaved() throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let model = try makeModel(suite: suite)

        #expect(model.width == 520)
        #expect(model.height == 340)
        #expect(PanelDefaultSizeModel.initialSize == CGSize(width: 520, height: 340))
        #expect(PanelDefaultSizeModel.widthRange == 320...4000)
        #expect(PanelDefaultSizeModel.heightRange == 160...4000)
        // @note p0-911
        #expect(Double(PanelDefaultSizeModel.widthRange.lowerBound) == PanelMetrics.defaultWidthRange.lowerBound)
        #expect(Double(PanelDefaultSizeModel.widthRange.upperBound) == PanelMetrics.defaultWidthRange.upperBound)
        #expect(Double(PanelDefaultSizeModel.heightRange.lowerBound) == PanelMetrics.defaultHeightRange.lowerBound)
        #expect(Double(PanelDefaultSizeModel.heightRange.upperBound) == PanelMetrics.defaultHeightRange.upperBound)
        #expect(PanelDefaultSizeModel.step == 10)

        model.width = 800
        model.height = 500
        #expect(model.width == 800)
        #expect(model.height == 500)

        let relaunched = try makeModel(suite: suite)
        #expect(relaunched.width == 800)
        #expect(relaunched.height == 500)
        #expect(try makeSettings(suite: suite).panelDefaultSize == CGSize(width: 800, height: 500))
    }

    @Test("AC-13: 範囲の外の数値は範囲の端になり、起動し直しても端の値のまま(初期値に戻らない)")
    func outOfRangeValuesAreClampedToEdges() throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let model = try makeModel(suite: suite)

        model.width = 100
        #expect(model.width == 320)
        model.height = 50
        #expect(model.height == 160)
        model.width = 99999
        #expect(model.width == 4000)

        let relaunched = try makeModel(suite: suite)
        #expect(relaunched.width == 4000)
        #expect(relaunched.height == 160)
    }

    // MARK: - 今のパネルの大きさを既定にする

    @Test("AC-14: パネルが大きさを保っていなければ押せず、呼んでも既定の大きさは変わらない")
    func cannotUseWhenPanelHoldsNoSize() throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let source = HeldPanelSizeSource()
        let model = try makeModel(suite: suite, source: source)

        #expect(source.size == nil)
        #expect(!model.canUseCurrentPanelSize)
        model.useCurrentPanelSize()
        #expect(model.width == 520)
        #expect(model.height == 340)
    }

    @Test("AC-14: 保っている大きさがあれば押せて、押すと四捨五入した幅と高さが既定になり、起動し直しても残り、押した後も押せる")
    func usesHeldPanelSize() throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let source = HeldPanelSizeSource()
        let model = try makeModel(suite: suite, source: source)

        source.size = CGSize(width: 700.4, height: 450.6)
        #expect(model.canUseCurrentPanelSize)
        model.useCurrentPanelSize()
        #expect(model.width == 700)
        #expect(model.height == 451)
        // @note p0-912
        #expect(model.canUseCurrentPanelSize)

        let relaunched = try makeModel(suite: suite)
        #expect(relaunched.width == 700)
        #expect(relaunched.height == 451)

        // @note p0-913
        source.size = CGSize(width: 5000, height: 100)
        model.useCurrentPanelSize()
        #expect(model.width == 4000)
        #expect(model.height == 160)
    }

    @Test("AC-14: 押せるかどうかは値を覚えず、設定画面を開いたまま保っている大きさが変わると(ドラッグ・挿入)読み直される")
    func canUseFollowsHeldSizeChanges() throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let source = HeldPanelSizeSource()
        let model = try makeModel(suite: suite, source: source)
        #expect(!model.canUseCurrentPanelSize)

        // @note p0-914
        let afterDrag = countCanUseChanges(of: model)
        source.size = CGSize(width: 600, height: 400)
        #expect(afterDrag.withLock { $0 } == 1)
        #expect(model.canUseCurrentPanelSize)

        // @note p0-915
        let afterInsert = countCanUseChanges(of: model)
        source.size = nil
        #expect(afterInsert.withLock { $0 } == 1)
        #expect(!model.canUseCurrentPanelSize)
    }

    // MARK: - 初期値に戻す

    @Test("AC-15: 「初期値に戻す」で 520×340 に戻り、起動し直しても 520×340")
    func resetsToInitialSize() throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let model = try makeModel(suite: suite)
        model.width = 800
        model.height = 500

        model.resetToInitial()
        #expect(model.width == 520)
        #expect(model.height == 340)

        let relaunched = try makeModel(suite: suite)
        #expect(relaunched.width == 520)
        #expect(relaunched.height == 340)

        // @note p0-916
        relaunched.resetToInitial()
        #expect(relaunched.width == 520)
        #expect(relaunched.height == 340)
    }
}
