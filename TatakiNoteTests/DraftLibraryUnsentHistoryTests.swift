import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct DraftLibraryUnsentHistoryTests {
    private func makeLibrary(
        in directory: DraftLibraryTestDirectory,
        historyLimit: Int = HistoryLimit.defaultValue
    ) -> DraftLibrary {
        DraftLibrary(
            store: DraftLibraryStore(directory: directory.dataDirectory),
            historyLimit: historyLimit,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }

    @Test("AC-1: 挿入していない文章は履歴の先頭に「挿入していない」として入り、読み直しても同じ本文・同じ印で残る")
    func unsentTextIsRecordedAtTheTop() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let library = makeLibrary(in: directory)
        library.recordInsertion(text: "inserted", appName: "Safari", bundleIdentifier: "com.apple.Safari")

        library.recordUnsentText("unsent\nline")

        let first = try #require(library.history.first)
        #expect(first.text == "unsent\nline")
        #expect(!first.isInserted)
        #expect(first.appName == nil)
        #expect(first.bundleIdentifier == nil)
        #expect(library.history.map(\.text) == ["unsent\nline", "inserted"])
        #expect(library.history.last?.isInserted == true)

        let reloaded = makeLibrary(in: directory)
        #expect(reloaded.history == library.history)
        #expect(reloaded.history.first?.isInserted == false)
        #expect(reloaded.history.first?.text == "unsent\nline")
        #expect(reloaded.history.last?.isInserted == true)
        #expect(reloaded.problems.isEmpty)
    }

    @Test("AC-2: 「挿入したか」の印が無い前の版の history.json は、すべて挿入した履歴として読め、退避も失敗の説明も出ない")
    func historyWithoutInsertedMarkIsReadAsInserted() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let json = """
        {"version":1,"history":[
        {"id":"\(UUID().uuidString)","text":"old one","insertedAt":"2026-10-06T05:32:00Z","appName":"Notes"},
        {"id":"\(UUID().uuidString)","text":"old two","insertedAt":"2026-10-05T05:32:00Z","appName":null,"bundleIdentifier":null}
        ]}
        """
        try directory.write(json, named: DraftLibraryStore.historyFileName)

        let library = makeLibrary(in: directory)

        #expect(library.history.map(\.text) == ["old one", "old two"])
        #expect(library.history.allSatisfy { $0.isInserted })
        #expect(library.history.first?.appName == "Notes")
        #expect(library.problems.isEmpty)
        #expect(!directory.fileNames().contains { $0.hasPrefix("history.unreadable-") })
        #expect(directory.fileNames().contains(DraftLibraryStore.historyFileName))
    }

    @Test("AC-3: 上限は挿入した履歴と挿入していない履歴の合計で数え、超えた分は古いものから外れる")
    func limitCountsBothKinds() {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let library = makeLibrary(in: directory, historyLimit: 20)

        for number in 1...25 {
            if number.isMultiple(of: 2) {
                library.recordInsertion(text: "entry \(number)", appName: nil, bundleIdentifier: nil)
            } else {
                library.recordUnsentText("entry \(number)")
            }
        }

        #expect(library.history.count == 20)
        #expect(library.history.first?.text == "entry 25")
        #expect(library.history.last?.text == "entry 6")
        #expect(!library.history.contains { $0.text == "entry 5" })
        #expect(makeLibrary(in: directory, historyLimit: 20).history.map(\.text) == library.history.map(\.text))
    }

    @Test("AC-3: 上限を指定しないと 200 件。範囲は 10〜1000 に丸める")
    func defaultAndClampedLimit() {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }

        #expect(makeLibrary(in: directory).historyLimit == 200)
        #expect(HistoryLimit.defaultValue == 200)
        #expect(HistoryLimit.range == 10...1000)
        #expect(HistoryLimit.clamped(9) == 10)
        #expect(HistoryLimit.clamped(10) == 10)
        #expect(HistoryLimit.clamped(1000) == 1000)
        #expect(HistoryLimit.clamped(1001) == 1000)
        #expect(HistoryLimit.clamped(-5) == 10)
        #expect(makeLibrary(in: directory, historyLimit: 3).historyLimit == 10)
        #expect(makeLibrary(in: directory, historyLimit: 5000).historyLimit == 1000)
    }

    @Test("AC-3: 読み込むときも上限で切る。上限を読み込みより先に決めるので、大きい上限の件数は切られない")
    func loadingIsCutByTheLimit() {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let writer = makeLibrary(in: directory, historyLimit: 30)
        for number in 1...30 {
            writer.recordUnsentText("entry \(number)")
        }
        #expect(writer.history.count == 30)

        let smaller = makeLibrary(in: directory, historyLimit: 20)
        #expect(smaller.history.count == 20)
        #expect(smaller.history.first?.text == "entry 30")
        #expect(smaller.history.last?.text == "entry 11")

        let largeDirectory = DraftLibraryTestDirectory()
        defer { largeDirectory.remove() }
        let largeWriter = makeLibrary(in: largeDirectory, historyLimit: 300)
        for number in 1...250 {
            largeWriter.recordInsertion(text: "entry \(number)", appName: nil, bundleIdentifier: nil)
        }
        #expect(largeWriter.history.count == 250)

        #expect(makeLibrary(in: largeDirectory, historyLimit: 300).history.count == 250)
    }

    @Test("AC-3: 上限を縮めると古いものが消えて保存先にも残らない。縮めなければ消えず、書き出さない")
    func shrinkingTheLimitDropsOldestAndPersists() {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let library = makeLibrary(in: directory, historyLimit: 30)
        for number in 1...30 {
            library.recordUnsentText("entry \(number)")
        }
        #expect(library.historyOverflow(forLimit: 30) == 0)
        #expect(library.historyOverflow(forLimit: 29) == 1)
        #expect(library.historyOverflow(forLimit: 20) == 10)
        #expect(library.historyOverflow(forLimit: 5) == 20)
        #expect(library.historyOverflow(forLimit: 5000) == 0)

        let fileBefore = directory.read(DraftLibraryStore.historyFileName)
        library.setHistoryLimit(30)
        #expect(library.history.count == 30)
        #expect(directory.read(DraftLibraryStore.historyFileName) == fileBefore)

        library.setHistoryLimit(29)
        #expect(library.historyLimit == 29)
        #expect(library.history.count == 29)
        #expect(library.history.last?.text == "entry 2")

        library.setHistoryLimit(20)
        #expect(library.history.count == 20)
        #expect(library.history.last?.text == "entry 11")

        let reloaded = makeLibrary(in: directory, historyLimit: 1000)
        #expect(reloaded.history.count == 20)
        #expect(reloaded.history.map(\.text) == library.history.map(\.text))
    }

    @Test("AC-31: 履歴の側が空のときの説明の件数は、ライブラリの上限になる")
    func emptyHistoryMessageFollowsTheLimit() throws {
        let defaults = try TemporaryDefaults()
        defer { defaults.remove() }
        let panel = PanelModel()
        let library = DraftLibrary(store: .inMemory, historyLimit: 300)
        let session = DraftSession(panel: panel, library: library, ownProcessIdentifier: 777)
        let model = SidebarModel(
            settings: defaults.makeSettings(),
            library: library,
            session: session,
            dateFormatter: { _ in "10月6日 14:32" }
        )

        model.tab = .history

        #expect(model.emptyMessage == "挿入した文章がここに残ります(最新 300 件)")
    }
}
