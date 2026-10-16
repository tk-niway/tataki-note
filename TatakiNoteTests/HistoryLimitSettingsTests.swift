import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct HistoryLimitSettingsTests {
    private struct Harness {
        let suiteName: String
        let defaults: UserDefaults
        let directory: DraftLibraryTestDirectory
        let settings: AppSettings
        let library: DraftLibrary
        let model: HistorySettingsModel

        func remove() {
            defaults.removePersistentDomain(forName: suiteName)
            directory.remove()
        }
    }

    private func makeHarness(limit: Int, entryCount: Int) throws -> Harness {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let directory = DraftLibraryTestDirectory()
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.historyLimit = limit
        let library = DraftLibrary(
            store: DraftLibraryStore(directory: directory.dataDirectory),
            historyLimit: settings.historyLimit
        )
        for index in 0..<entryCount {
            library.recordInsertion(text: "entry \(index)", appName: "Notes", bundleIdentifier: nil)
        }
        return Harness(
            suiteName: suiteName,
            defaults: defaults,
            directory: directory,
            settings: settings,
            library: library,
            model: HistorySettingsModel(library: library, settings: settings)
        )
    }

    private func reloadedHistory(of harness: Harness, limit: Int = HistoryLimit.range.upperBound) -> [HistoryEntry] {
        DraftLibrary(store: DraftLibraryStore(directory: harness.directory.dataDirectory), historyLimit: limit).history
    }

    // MARK: - AC-29

    @Test("AC-29: 保存したキーが無ければ、履歴の上限は 200 件")
    func defaultLimitWithoutStoredKey() throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)

        #expect(store.loadHistoryLimit() == 200)
        #expect(AppSettings(store: store).historyLimit == 200)
    }

    @Test("AC-29: 保存した上限は、設定を作り直して読んでも同じ。範囲外は丸めて保存する")
    func savedLimitSurvivesRecreation() throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)
        let settings = AppSettings(store: store)

        settings.historyLimit = 250
        #expect(AppSettings(store: store).historyLimit == 250)

        settings.historyLimit = 5000
        #expect(settings.historyLimit == 1000)
        #expect(AppSettings(store: store).historyLimit == 1000)
        #expect(defaults.integer(forKey: SettingsStore.Key.historyLimit) == 1000)

        settings.historyLimit = 3
        #expect(settings.historyLimit == 10)
        #expect(AppSettings(store: store).historyLimit == 10)
    }

    @Test("AC-29: 保存してある値が範囲外・数値でないときは、範囲の端か初期値になる(1e30 でも落ちない)")
    func storedValuesAreClampedOrFallBack() throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)
        let cases: [(stored: Any, expected: Int)] = [
            (5, 10),
            (5000, 1000),
            (1e30, 1000),
            (-1e30, 10),
            (Double.infinity, 200),
            ("abc", 200),
            (true, 200),
            (250.7, 250),
        ]

        for (stored, expected) in cases {
            defaults.set(stored, forKey: SettingsStore.Key.historyLimit)
            #expect(store.loadHistoryLimit() == expected, "\(stored)")
            #expect(AppSettings(store: store).historyLimit == expected, "\(stored)")
        }
    }

    @Test("AC-29: 今の件数以上にする上限は、確認なしで設定とライブラリの両方が変わる")
    func limitAtLeastCurrentCountChangesWithoutConfirmation() throws {
        let harness = try makeHarness(limit: 50, entryCount: 30)
        defer { harness.remove() }

        harness.model.requestHistoryLimit(100)
        #expect(harness.model.pendingLimit == nil)
        #expect(harness.settings.historyLimit == 100)
        #expect(harness.library.historyLimit == 100)
        #expect(harness.model.historyLimit == 100)
        #expect(harness.library.history.count == 30)

        harness.model.requestHistoryLimit(30)
        #expect(harness.model.pendingLimit == nil)
        #expect(harness.settings.historyLimit == 30)
        #expect(harness.library.historyLimit == 30)
        #expect(harness.library.history.count == 30)
        #expect(SettingsStore(defaults: harness.defaults).loadHistoryLimit() == 30)
    }

    @Test("AC-29: 範囲外の上限は丸めてから判定する(5000 は 1000 に)")
    func outOfRangeLimitIsClampedBeforeTheCheck() throws {
        let harness = try makeHarness(limit: 50, entryCount: 3)
        defer { harness.remove() }

        harness.model.requestHistoryLimit(5000)

        #expect(harness.model.pendingLimit == nil)
        #expect(harness.settings.historyLimit == 1000)
        #expect(harness.library.historyLimit == 1000)
    }

    @Test("AC-29: 今の上限と同じ値を入れても何も起きない")
    func sameLimitDoesNothing() throws {
        let harness = try makeHarness(limit: 50, entryCount: 30)
        defer { harness.remove() }

        harness.model.requestHistoryLimit(50)

        #expect(harness.model.pendingLimit == nil)
        #expect(harness.library.history.count == 30)
        #expect(harness.settings.historyLimit == 50)
    }

    // MARK: - AC-30

    @Test("AC-30: 件数より小さい上限を入れると、消える件数の確認になり、上限はまだ変わらない")
    func shrinkingBelowCountAsksFirst() throws {
        let harness = try makeHarness(limit: 50, entryCount: 30)
        defer { harness.remove() }

        harness.model.requestHistoryLimit(20)

        #expect(harness.model.pendingLimit == HistorySettingsModel.PendingHistoryLimit(limit: 20, removedCount: 10))
        #expect(harness.model.historyLimit == 50)
        #expect(harness.settings.historyLimit == 50)
        #expect(harness.library.historyLimit == 50)
        #expect(harness.library.history.count == 30)
    }

    @Test("AC-30: 範囲外の小さい値は 10 に丸めた件数で確認する")
    func shrinkingOutOfRangeIsClamped() throws {
        let harness = try makeHarness(limit: 50, entryCount: 30)
        defer { harness.remove() }

        harness.model.requestHistoryLimit(5)

        #expect(harness.model.pendingLimit == HistorySettingsModel.PendingHistoryLimit(limit: 10, removedCount: 20))
    }

    @Test("AC-30: 確定すると、古い履歴がその件数だけ消えて上限が変わり、読み直しても消えたまま")
    func confirmingRemovesOldestAndKeepsItRemoved() throws {
        let harness = try makeHarness(limit: 50, entryCount: 30)
        defer { harness.remove() }
        let newest = harness.library.history.prefix(20).map(\.text)

        harness.model.requestHistoryLimit(20)
        harness.model.confirmHistoryLimit()

        #expect(harness.model.pendingLimit == nil)
        #expect(harness.library.historyLimit == 20)
        #expect(harness.settings.historyLimit == 20)
        #expect(harness.library.history.map(\.text) == newest)
        #expect(SettingsStore(defaults: harness.defaults).loadHistoryLimit() == 20)
        #expect(reloadedHistory(of: harness).map(\.text) == newest)
    }

    @Test("AC-30: 確認中に履歴が増えても、確定のときはその時点の件数で古いものを消す")
    func confirmingUsesTheCountAtConfirmation() throws {
        let harness = try makeHarness(limit: 50, entryCount: 30)
        defer { harness.remove() }

        harness.model.requestHistoryLimit(20)
        harness.library.recordInsertion(text: "later", appName: nil, bundleIdentifier: nil)
        #expect(harness.model.pendingLimit?.removedCount == 10)

        harness.model.confirmHistoryLimit()

        #expect(harness.library.history.count == 20)
        #expect(harness.library.history.first?.text == "later")
    }

    @Test("AC-30: キャンセルすると、上限も履歴も変わらず、入力欄を戻す数が増える")
    func cancellingKeepsLimitAndHistory() throws {
        let harness = try makeHarness(limit: 50, entryCount: 30)
        defer { harness.remove() }
        let before = harness.library.history
        let resetCount = harness.model.limitFieldResetCount

        harness.model.requestHistoryLimit(20)
        harness.model.cancelHistoryLimit()

        #expect(harness.model.pendingLimit == nil)
        #expect(harness.model.historyLimit == 50)
        #expect(harness.settings.historyLimit == 50)
        #expect(harness.library.history == before)
        #expect(harness.model.limitFieldResetCount == resetCount + 1)
        #expect(reloadedHistory(of: harness).count == 30)
    }

    @Test("AC-30: 確認中でないときの「変更する」では何も変わらない")
    func confirmingWithoutRequestDoesNothing() throws {
        let harness = try makeHarness(limit: 50, entryCount: 30)
        defer { harness.remove() }

        harness.model.confirmHistoryLimit()

        #expect(harness.library.historyLimit == 50)
        #expect(harness.library.history.count == 30)
    }

    @Test("AC-30: 上限の確認中に「履歴をすべて削除」を押すと、上限の確認を閉じて削除の確認になる")
    func clearRequestClosesLimitConfirmation() throws {
        let harness = try makeHarness(limit: 50, entryCount: 30)
        defer { harness.remove() }

        harness.model.requestHistoryLimit(20)
        harness.model.requestClear()

        #expect(harness.model.pendingLimit == nil)
        #expect(harness.model.phase == .confirming)
        #expect(harness.library.historyLimit == 50)
        #expect(harness.library.history.count == 30)
    }

    @Test("AC-30: 削除の確認中に縮める上限を入れると、削除の確認を閉じて上限の確認になる")
    func shrinkRequestClosesClearConfirmation() throws {
        let harness = try makeHarness(limit: 50, entryCount: 30)
        defer { harness.remove() }

        harness.model.requestClear()
        harness.model.requestHistoryLimit(20)

        #expect(harness.model.phase == .idle)
        #expect(harness.model.pendingLimit != nil)
        #expect(harness.library.history.count == 30)
    }

    @Test("AC-30: 削除の確認中に今の件数以上の上限を入れても、削除の確認は開いたまま")
    func growRequestKeepsClearConfirmation() throws {
        let harness = try makeHarness(limit: 50, entryCount: 30)
        defer { harness.remove() }

        harness.model.requestClear()
        harness.model.requestHistoryLimit(100)

        #expect(harness.model.phase == .confirming)
        #expect(harness.model.pendingLimit == nil)
        #expect(harness.library.historyLimit == 100)
    }

    @Test("AC-30: 設定の窓を閉じると、上限の確認は閉じて上限は変わらない")
    func resetPhaseClosesLimitConfirmation() throws {
        let harness = try makeHarness(limit: 50, entryCount: 30)
        defer { harness.remove() }

        harness.model.requestHistoryLimit(20)
        harness.model.resetPhase()

        #expect(harness.model.pendingLimit == nil)
        #expect(harness.library.historyLimit == 50)
        #expect(harness.settings.historyLimit == 50)
        #expect(harness.library.history.count == 30)
    }
}
