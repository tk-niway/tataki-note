import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct HistoryRetentionTests {
    private static let origin = Date(timeIntervalSince1970: 1_700_000_000)
    private static let day: TimeInterval = 86_400

    @MainActor
    private final class TestClock {
        var current: Date

        init(_ date: Date = HistoryRetentionTests.origin) {
            current = date
        }

        func advance(by seconds: TimeInterval) {
            current = current.addingTimeInterval(seconds)
        }
    }

    private func makeLibrary(
        in directory: DraftLibraryTestDirectory,
        clock: TestClock,
        historyLimit: Int = HistoryLimit.defaultValue,
        retention: HistoryRetention = .forever
    ) -> DraftLibrary {
        DraftLibrary(
            store: DraftLibraryStore(directory: directory.dataDirectory),
            historyLimit: historyLimit,
            historyRetention: retention,
            now: { clock.current }
        )
    }

    private func historyFileURL(in directory: DraftLibraryTestDirectory) -> URL {
        directory.dataDirectory.appendingPathComponent(DraftLibraryStore.historyFileName)
    }

    // MARK: - AC-4

    @Test("AC-4: 選択肢は無期限・30日・7日・1日の順で、初期値は無期限、期間の長さは 30日・7日・1日の秒数")
    func optionsAndDefault() {
        #expect(HistoryRetention.allCases == [.forever, .thirtyDays, .sevenDays, .oneDay])
        #expect(HistoryRetention.allCases.map(\.displayName) == ["無期限", "30日", "7日", "1日"])
        #expect(HistoryRetention.defaultValue == .forever)
        #expect(HistoryRetention.allCases.map(\.duration) == [nil, 30 * Self.day, 7 * Self.day, Self.day])
    }

    @Test("AC-4: 保存の値が無ければ無期限で、選んだ期間は作り直した設定でも残る")
    func selectedRetentionPersists() throws {
        let temporary = try TemporaryDefaults()
        defer { temporary.remove() }
        #expect(temporary.makeSettings().historyRetention == .forever)

        for retention in HistoryRetention.allCases {
            temporary.makeSettings().historyRetention = retention
            #expect(temporary.makeSettings().historyRetention == retention)
        }
    }

    @Test("AC-4: 保存の値が文字列でない・知らない値なら無期限になる")
    func invalidStoredValueFallsBackToForever() throws {
        let temporary = try TemporaryDefaults()
        defer { temporary.remove() }
        let store = SettingsStore(defaults: temporary.defaults)

        temporary.defaults.set("fortnight", forKey: SettingsStore.Key.historyRetention)
        #expect(store.loadHistoryRetention() == .forever)

        temporary.defaults.set(7, forKey: SettingsStore.Key.historyRetention)
        #expect(store.loadHistoryRetention() == .forever)

        temporary.defaults.set("", forKey: SettingsStore.Key.historyRetention)
        #expect(store.loadHistoryRetention() == .forever)
    }

    // MARK: - AC-5

    @Test("AC-5: 期間の境界は、ちょうど期間の長さだけ前のものが消え、1秒新しいものと未来の日時は残る")
    func expirationBoundary() {
        let now = Self.origin
        for retention in [HistoryRetention.thirtyDays, .sevenDays, .oneDay] {
            let length = retention.duration ?? 0
            #expect(retention.isExpired(now.addingTimeInterval(-length), now: now))
            #expect(retention.isExpired(now.addingTimeInterval(-length - 1), now: now))
            #expect(!retention.isExpired(now.addingTimeInterval(-length + 1), now: now))
            #expect(!retention.isExpired(now.addingTimeInterval(60), now: now))
        }
    }

    @Test("AC-5: 起動時の読み込みで期間を過ぎた履歴(挿入した文章と履歴に移った書きかけ)が消え、ファイルを読み直しても無い")
    func expiredHistoryIsRemovedOnLoad() {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let clock = TestClock()
        let writer = makeLibrary(in: directory, clock: clock)
        writer.recordInsertion(text: "inserted old", appName: "Notes", bundleIdentifier: "com.apple.Notes")
        clock.advance(by: 1)
        writer.recordUnsentText("unsent old")
        clock.advance(by: 1)
        writer.recordInsertion(text: "boundary newer", appName: nil, bundleIdentifier: nil)

        clock.current = Self.origin.addingTimeInterval(Self.day + 1)
        let library = makeLibrary(in: directory, clock: clock, retention: .oneDay)

        #expect(library.history.map(\.text) == ["boundary newer"])
        let reloaded = makeLibrary(in: directory, clock: clock)
        #expect(reloaded.history.map(\.text) == ["boundary newer"])
    }

    @Test("AC-5: 読み込みのとき、ちょうど期間の長さだけ前の履歴は消え、1秒新しい履歴は残る")
    func loadBoundary() {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let clock = TestClock()
        let writer = makeLibrary(in: directory, clock: clock)
        writer.recordInsertion(text: "exactly one day", appName: nil, bundleIdentifier: nil)
        clock.advance(by: 1)
        writer.recordUnsentText("one second newer")

        clock.current = Self.origin.addingTimeInterval(Self.day)
        let library = makeLibrary(in: directory, clock: clock, retention: .oneDay)

        #expect(library.history.map(\.text) == ["one second newer"])
        #expect(makeLibrary(in: directory, clock: clock).history.map(\.text) == ["one second newer"])
    }

    @Test("AC-5: 新しい記録のとき、期間を過ぎた履歴が消え、ファイルを読み直しても無い")
    func expiredHistoryIsRemovedOnRecord() {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let clock = TestClock()
        let library = makeLibrary(in: directory, clock: clock, retention: .oneDay)
        library.recordUnsentText("unsent old")
        clock.advance(by: 1)
        library.recordInsertion(text: "inserted newer", appName: nil, bundleIdentifier: nil)

        clock.current = Self.origin.addingTimeInterval(Self.day)
        library.recordInsertion(text: "fresh", appName: nil, bundleIdentifier: nil)

        #expect(library.history.map(\.text) == ["fresh", "inserted newer"])
        #expect(makeLibrary(in: directory, clock: clock).history.map(\.text) == ["fresh", "inserted newer"])
    }

    @Test("AC-5: 期間を短くすると期間を過ぎた履歴が消え、消える件数は変える前に分かり、ファイルを読み直しても無い")
    func expiredHistoryIsRemovedOnRetentionChange() {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let clock = TestClock()
        let library = makeLibrary(in: directory, clock: clock)
        library.recordInsertion(text: "ten days old", appName: nil, bundleIdentifier: nil)
        clock.advance(by: 5 * Self.day)
        library.recordUnsentText("five days old")
        clock.advance(by: 5 * Self.day)
        library.recordInsertion(text: "today", appName: nil, bundleIdentifier: nil)

        #expect(library.expiredHistoryCount(for: .forever) == 0)
        #expect(library.expiredHistoryCount(for: .thirtyDays) == 0)
        #expect(library.expiredHistoryCount(for: .sevenDays) == 1)
        #expect(library.expiredHistoryCount(for: .oneDay) == 2)
        #expect(library.history.count == 3)
        #expect(library.historyRetention == .forever)

        library.setHistoryRetention(.sevenDays)

        #expect(library.historyRetention == .sevenDays)
        #expect(library.history.map(\.text) == ["today", "five days old"])
        #expect(makeLibrary(in: directory, clock: clock).history.map(\.text) == ["today", "five days old"])
    }

    // MARK: - AC-6

    @Test("AC-6: 保存した下書きは、期間を過ぎても読み込み・記録・期間の変更で消えない")
    func savedDraftsAreKept() {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let clock = TestClock()
        let writer = makeLibrary(in: directory, clock: clock)
        writer.addDraft(text: "saved draft")
        writer.recordInsertion(text: "history", appName: nil, bundleIdentifier: nil)

        clock.advance(by: 100 * Self.day)
        let library = makeLibrary(in: directory, clock: clock, retention: .oneDay)
        #expect(library.history.isEmpty)
        #expect(library.drafts.map(\.text) == ["saved draft"])

        library.recordInsertion(text: "fresh", appName: nil, bundleIdentifier: nil)
        library.setHistoryRetention(.oneDay)
        #expect(library.drafts.map(\.text) == ["saved draft"])

        #expect(makeLibrary(in: directory, clock: clock).drafts.map(\.text) == ["saved draft"])
    }

    // MARK: - AC-7

    @Test("AC-7: 期間内でも件数を超えた古い履歴は消え、件数内でも期間を過ぎた履歴は消える")
    func retentionAndLimitBothApply() {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let clock = TestClock()
        let limit = HistoryLimit.range.lowerBound
        let library = makeLibrary(in: directory, clock: clock, historyLimit: limit, retention: .oneDay)
        for index in 0..<(limit + 2) {
            library.recordUnsentText("entry \(index)")
            clock.advance(by: 3_600)
        }

        #expect(library.history.count == limit)
        #expect(library.history.first?.text == "entry \(limit + 1)")
        #expect(library.history.last?.text == "entry 2")

        clock.current = Self.origin.addingTimeInterval(31 * 3_600)
        library.pruneExpiredHistory()

        let expected = (8..<(limit + 2)).reversed().map { "entry \($0)" }
        #expect(library.history.map(\.text) == expected)
        #expect(library.history.count < limit)
        #expect(makeLibrary(in: directory, clock: clock, historyLimit: limit).history.map(\.text) == expected)
    }

    // MARK: - AC-8

    @Test("AC-8: 無期限なら、どれだけ古い履歴も読み込み・記録・期間の変更で消えない")
    func foreverKeepsEverything() {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let clock = TestClock()
        let writer = makeLibrary(in: directory, clock: clock)
        writer.recordInsertion(text: "ancient", appName: nil, bundleIdentifier: nil)

        clock.advance(by: 3_650 * Self.day)
        let library = makeLibrary(in: directory, clock: clock)
        #expect(library.history.map(\.text) == ["ancient"])

        library.recordUnsentText("recent")
        library.setHistoryRetention(.forever)
        library.pruneExpiredHistory()

        #expect(library.history.map(\.text) == ["recent", "ancient"])
        #expect(library.expiredHistoryCount(for: .forever) == 0)
        #expect(makeLibrary(in: directory, clock: clock).history.map(\.text) == ["recent", "ancient"])
    }

    @Test("AC-8: 無期限のとき、期限切れの削除は何も書き出さない")
    func foreverWritesNothing() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let clock = TestClock()
        let writer = makeLibrary(in: directory, clock: clock)
        writer.recordInsertion(text: "ancient", appName: nil, bundleIdentifier: nil)
        clock.advance(by: 3_650 * Self.day)
        let library = makeLibrary(in: directory, clock: clock)
        try FileManager.default.removeItem(at: historyFileURL(in: directory))

        library.pruneExpiredHistory()
        library.setHistoryRetention(.forever)

        #expect(!directory.fileNames().contains(DraftLibraryStore.historyFileName))
    }

    @Test("AC-8: 消える履歴が無いときは、期間があっても書き出さない")
    func nothingExpiredWritesNothing() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let clock = TestClock()
        let library = makeLibrary(in: directory, clock: clock, retention: .oneDay)
        library.recordInsertion(text: "fresh", appName: nil, bundleIdentifier: nil)
        try FileManager.default.removeItem(at: historyFileURL(in: directory))

        library.pruneExpiredHistory()
        library.setHistoryRetention(.sevenDays)

        #expect(library.history.map(\.text) == ["fresh"])
        #expect(!directory.fileNames().contains(DraftLibraryStore.historyFileName))
    }
}
