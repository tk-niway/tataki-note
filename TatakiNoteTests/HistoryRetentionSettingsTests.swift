import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct HistoryRetentionSettingsTests {
    private static let origin = Date(timeIntervalSince1970: 1_700_000_000)
    private static let day: TimeInterval = 86_400

    @MainActor
    private final class TestClock {
        var current = HistoryRetentionSettingsTests.origin

        func advance(by seconds: TimeInterval) {
            current = current.addingTimeInterval(seconds)
        }
    }

    private struct Harness {
        let suiteName: String
        let defaults: InMemoryDefaults
        let directory: DraftLibraryTestDirectory
        let clock: TestClock
        let settings: AppSettings
        let library: DraftLibrary
        let model: HistorySettingsModel

        func remove() {
            defaults.removePersistentDomain(forName: suiteName)
            directory.remove()
        }
    }

    private func makeHarness(
        retention: HistoryRetention = .forever,
        oldCount: Int,
        recentCount: Int = 0,
        gap: TimeInterval = 2 * HistoryRetentionSettingsTests.day
    ) throws -> Harness {
        let suiteName = UUID().uuidString
        let defaults = try #require(InMemoryDefaults(suiteName: suiteName))
        let directory = DraftLibraryTestDirectory()
        let clock = TestClock()
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.historyRetention = retention
        let library = DraftLibrary(
            store: DraftLibraryStore(directory: directory.dataDirectory),
            historyRetention: retention,
            now: { clock.current }
        )
        for index in 0..<oldCount {
            library.recordInsertion(text: "old \(index)", appName: "Notes", bundleIdentifier: nil)
        }
        clock.advance(by: gap)
        for index in 0..<recentCount {
            library.recordInsertion(text: "recent \(index)", appName: "Notes", bundleIdentifier: nil)
        }
        return Harness(
            suiteName: suiteName,
            defaults: defaults,
            directory: directory,
            clock: clock,
            settings: settings,
            library: library,
            model: HistorySettingsModel(library: library, settings: settings)
        )
    }

    private func reloadedHistory(of harness: Harness, retention: HistoryRetention = .forever) -> [HistoryEntry] {
        DraftLibrary(
            store: DraftLibraryStore(directory: harness.directory.dataDirectory),
            historyRetention: retention,
            now: { harness.clock.current }
        ).history
    }

    // MARK: - AC-9

    @Test("AC-9: 消える履歴が無い期間を選ぶと、確認なしですぐ期間が変わる")
    func changesImmediatelyWhenNothingExpires() throws {
        let harness = try makeHarness(oldCount: 0, recentCount: 3)
        defer { harness.remove() }

        harness.model.requestHistoryRetention(.oneDay)

        #expect(harness.model.pendingRetention == nil)
        #expect(harness.model.historyRetention == .oneDay)
        #expect(harness.library.historyRetention == .oneDay)
        #expect(harness.settings.historyRetention == .oneDay)
        #expect(harness.library.history.count == 3)
    }

    @Test("AC-9: 今と同じ期間を選んでも何も変わらない")
    func sameRetentionDoesNothing() throws {
        let harness = try makeHarness(oldCount: 2)
        defer { harness.remove() }

        harness.model.requestHistoryRetention(.forever)

        #expect(harness.model.pendingRetention == nil)
        #expect(harness.model.historyRetention == .forever)
        #expect(harness.library.history.count == 2)
    }

    @Test("AC-9: 消える履歴があるときは、消える件数を示す確認に移り、期間も履歴もまだ変わらない")
    func movesToConfirmationWhenSomethingExpires() throws {
        let harness = try makeHarness(oldCount: 3, recentCount: 2)
        defer { harness.remove() }

        harness.model.requestHistoryRetention(.oneDay)

        #expect(harness.model.pendingRetention == HistorySettingsModel.PendingHistoryRetention(retention: .oneDay, removedCount: 3))
        #expect(harness.model.historyRetention == .forever)
        #expect(harness.settings.historyRetention == .forever)
        #expect(harness.library.history.count == 5)
    }

    @Test("AC-9: 「変更する」で期間が変わって古い履歴が消え、保存した下書きは残り、ファイルを読み直しても同じ")
    func confirmChangesRetentionAndRemovesOldEntries() throws {
        let harness = try makeHarness(oldCount: 3, recentCount: 2)
        defer { harness.remove() }
        let draft = try #require(harness.library.addDraft(text: "kept draft"))

        harness.model.requestHistoryRetention(.oneDay)
        harness.model.confirmHistoryRetention()

        #expect(harness.model.pendingRetention == nil)
        #expect(harness.model.historyRetention == .oneDay)
        #expect(harness.library.historyRetention == .oneDay)
        #expect(harness.settings.historyRetention == .oneDay)
        #expect(harness.model.historyCount == 2)
        #expect(harness.library.history.allSatisfy { $0.text.hasPrefix("recent") })
        #expect(harness.library.draft(id: draft.id) != nil)
        #expect(reloadedHistory(of: harness).count == 2)
    }

    @Test("AC-9: 「キャンセル」では期間も履歴も変わらない")
    func cancelChangesNothing() throws {
        let harness = try makeHarness(oldCount: 3, recentCount: 2)
        defer { harness.remove() }

        harness.model.requestHistoryRetention(.oneDay)
        harness.model.cancelHistoryRetention()

        #expect(harness.model.pendingRetention == nil)
        #expect(harness.model.historyRetention == .forever)
        #expect(harness.settings.historyRetention == .forever)
        #expect(harness.library.history.count == 5)
        #expect(reloadedHistory(of: harness).count == 5)
    }

    @Test("AC-9: 確認中でないときの「変更する」では何も変わらない")
    func confirmWithoutRequestDoesNothing() throws {
        let harness = try makeHarness(oldCount: 3)
        defer { harness.remove() }

        harness.model.confirmHistoryRetention()

        #expect(harness.model.historyRetention == .forever)
        #expect(harness.library.history.count == 3)
    }

    @Test("AC-9: 確認中に別の期間を選ぶと、その期間の判定で確認が置き換わる")
    func anotherRetentionReplacesConfirmation() throws {
        let harness = try makeHarness(oldCount: 3, recentCount: 1)
        defer { harness.remove() }

        harness.model.requestHistoryRetention(.oneDay)
        harness.model.requestHistoryRetention(.thirtyDays)

        #expect(harness.model.pendingRetention == nil)
        #expect(harness.model.historyRetention == .thirtyDays)
        #expect(harness.library.history.count == 4)
    }

    @Test("AC-9: 確認中に「履歴をすべて削除」を押すと、期間の確認は閉じて削除の確認になる")
    func clearRequestClosesRetentionConfirmation() throws {
        let harness = try makeHarness(oldCount: 3)
        defer { harness.remove() }

        harness.model.requestHistoryRetention(.oneDay)
        harness.model.requestClear()

        #expect(harness.model.pendingRetention == nil)
        #expect(harness.model.phase == .confirming)
        #expect(harness.model.historyRetention == .forever)
        #expect(harness.library.history.count == 3)
    }

    @Test("AC-9: 確認中に残す件数を変えると、期間の確認は閉じて件数の判定に移る")
    func limitRequestClosesRetentionConfirmation() throws {
        let harness = try makeHarness(oldCount: 30)
        defer { harness.remove() }

        harness.model.requestHistoryRetention(.oneDay)
        harness.model.requestHistoryLimit(10)

        #expect(harness.model.pendingRetention == nil)
        #expect(harness.model.pendingLimit == HistorySettingsModel.PendingHistoryLimit(limit: 10, removedCount: 20))
        #expect(harness.model.historyRetention == .forever)
        #expect(harness.library.history.count == 30)
    }

    @Test("AC-9: 件数の確認中・削除の確認中に期間を選ぶと、それらは閉じて期間の確認になる")
    func retentionRequestClosesOtherConfirmations() throws {
        let harness = try makeHarness(oldCount: 30)
        defer { harness.remove() }

        harness.model.requestHistoryLimit(10)
        #expect(harness.model.pendingLimit != nil)
        harness.model.requestHistoryRetention(.oneDay)
        #expect(harness.model.pendingLimit == nil)
        #expect(harness.model.pendingRetention?.removedCount == 30)

        harness.model.cancelHistoryRetention()
        harness.model.requestClear()
        #expect(harness.model.phase == .confirming)
        harness.model.requestHistoryRetention(.oneDay)
        #expect(harness.model.phase == .idle)
        #expect(harness.model.pendingRetention?.removedCount == 30)
        #expect(harness.library.history.count == 30)
    }

    @Test("AC-9: 別の項目への切り替え・窓を閉じたとき(resetPhase)は、確認が閉じて何も変わらない")
    func resetPhaseClosesRetentionConfirmation() throws {
        let harness = try makeHarness(oldCount: 3, recentCount: 2)
        defer { harness.remove() }

        harness.model.requestHistoryRetention(.oneDay)
        harness.model.resetPhase()

        #expect(harness.model.pendingRetention == nil)
        #expect(harness.model.historyRetention == .forever)
        #expect(harness.settings.historyRetention == .forever)
        #expect(harness.library.history.count == 5)
    }

    @Test("AC-9: 確認の間に履歴が増えても、「変更する」ではその時点で期限切れのものを消す")
    func confirmUsesTheCurrentHistory() throws {
        let harness = try makeHarness(oldCount: 3)
        defer { harness.remove() }

        harness.model.requestHistoryRetention(.oneDay)
        harness.library.recordInsertion(text: "added during confirmation", appName: "Notes", bundleIdentifier: nil)
        harness.model.confirmHistoryRetention()

        #expect(harness.library.history.map(\.text) == ["added during confirmation"])
    }

    // MARK: - AC-11

    @Test("AC-11: 期間の説明文は「これより古い履歴は消えます。⌘S で保存した下書きは消えません。」")
    func retentionHelpText() {
        #expect(SettingsHelpText.historyRetention == "これより古い履歴は消えます。⌘S で保存した下書きは消えません。")
    }

    @Test("AC-11: 警告は「「1日」にすると、古い履歴が 3 件消えます。この操作は元に戻せません。」の形")
    func retentionWarningText() {
        #expect(
            SettingsHelpText.historyRetentionWarning(retention: .oneDay, removedCount: 3)
                == "「1日」にすると、古い履歴が 3 件消えます。この操作は元に戻せません。"
        )
        #expect(
            SettingsHelpText.historyRetentionWarning(retention: .thirtyDays, removedCount: 12)
                == "「30日」にすると、古い履歴が 12 件消えます。この操作は元に戻せません。"
        )
    }

    // MARK: - AC-12

    @Test("AC-12: 設定画面の履歴のモデルは、期間を過ぎた履歴を消して件数に出さず、ファイルからも消える")
    func removeExpiredHistoryDropsOldEntries() throws {
        let harness = try makeHarness(retention: .oneDay, oldCount: 3, recentCount: 1, gap: Self.day / 2)
        defer { harness.remove() }
        harness.clock.advance(by: Self.day / 2 + 1)
        #expect(harness.model.historyCount == 4)

        harness.model.removeExpiredHistory()

        #expect(harness.model.historyCount == 1)
        #expect(harness.library.history.map(\.text) == ["recent 0"])
        #expect(reloadedHistory(of: harness, retention: .forever).map(\.text) == ["recent 0"])
    }

    @Test("AC-12: 設定画面を開くと、期間を過ぎた履歴が消えて設定の件数に出ない")
    func openingSettingsRemovesExpiredHistory() throws {
        let harness = try makeHarness(retention: .oneDay, oldCount: 3, recentCount: 1, gap: Self.day / 2)
        defer { harness.remove() }
        harness.clock.advance(by: Self.day / 2 + 1)
        #expect(harness.model.historyCount == 4)

        let controller = SettingsWindowController(
            settings: harness.settings,
            launchAtLogin: LaunchAtLoginModel(service: InMemoryLoginItemService()),
            appInfo: AppInfoModel(
                infoDictionary: [:],
                permissionStatus: PermissionGuideModel(permission: OverriddenAccessibilityPermission(isTrusted: true))
            ),
            panelDefaultSize: PanelDefaultSizeModel(settings: harness.settings, currentPanelSize: { nil }),
            library: harness.library
        )
        let before = Set(NSApp.windows.map { ObjectIdentifier($0) })
        controller.show()
        defer {
            NSApp.windows
                .filter { !before.contains(ObjectIdentifier($0)) && $0.identifier?.rawValue == "settings" }
                .forEach { $0.close() }
        }

        #expect(controller.history.historyCount == 1)
        #expect(harness.library.history.map(\.text) == ["recent 0"])
    }

    @Test("AC-12: パネルを開くと、期間を過ぎた履歴が消えてサイドバーの一覧に出ない")
    func openingPanelRemovesExpiredHistory() throws {
        let harness = try makeHarness(retention: .oneDay, oldCount: 3, recentCount: 1, gap: Self.day / 2)
        defer { harness.remove() }
        harness.clock.advance(by: Self.day / 2 + 1)
        #expect(harness.library.history.count == 4)

        let probe = FocusedElementProbeStub()
        let controller = PanelController(
            settings: harness.settings,
            targetTracker: FrontmostAppTracker(workspace: .shared, ownProcessIdentifier: -1),
            inserter: InserterStub(result: .inserted),
            permission: PermissionStub(isTrusted: true),
            fieldProbe: probe,
            library: harness.library,
            beep: {},
            makeTargetMonitor: InsertionTargetMonitor.testFactory(
                probe: probe,
                ownProcessIdentifier: ProcessInfo.processInfo.processIdentifier
            )
        )
        defer { controller.close() }

        controller.targetOverride = { InsertionTarget(processIdentifier: 101, bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit") }
        controller.open()

        #expect(harness.library.history.map(\.text) == ["recent 0"])
        #expect(controller.sidebarModel.count(of: .history) == 1)
    }
}
