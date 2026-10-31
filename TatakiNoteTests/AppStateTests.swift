import Foundation
import Observation
import os
import Testing
@testable import TatakiNote

@MainActor
struct AppStateTests {
    private func makeStore() throws -> (SettingsStore, TemporaryDefaults) {
        let temporary = try TemporaryDefaults()
        return (SettingsStore(defaults: temporary.defaults), temporary)
    }

    @Test("AC-7: 6つの状態を AppState で変えると、同じ保存先で作り直しても残る")
    func stateSurvivesRecreation() throws {
        let (store, temporary) = try makeStore()
        defer { temporary.remove() }
        let checked = Date(timeIntervalSince1970: 1_800_000_000)
        let state = AppState(store: store)
        state.hasShownFirstLaunchTutorial = true
        state.isSidebarOpen = true
        state.sidebarTab = .history
        state.lastExportDirectoryPath = "/tmp/export"
        state.lastUpdateCheckDate = checked
        state.suppressesMoveToApplicationsPrompt = true

        let reloaded = AppState(store: store)
        #expect(reloaded.hasShownFirstLaunchTutorial)
        #expect(reloaded.isSidebarOpen)
        #expect(reloaded.sidebarTab == .history)
        #expect(reloaded.lastExportDirectoryPath == "/tmp/export")
        #expect(reloaded.lastUpdateCheckDate == checked)
        #expect(reloaded.suppressesMoveToApplicationsPrompt)
    }

    @Test("AC-7: AppSettings.state は同じ保存先を使い、state で変えた値を新しい AppSettings の state が読む")
    func settingsStateSharesStorage() throws {
        let temporary = try TemporaryDefaults()
        defer { temporary.remove() }
        let settings = temporary.makeSettings()
        settings.state.isSidebarOpen = true
        settings.state.sidebarTab = .history
        settings.state.lastExportDirectoryPath = "/tmp/shared"

        let other = temporary.makeSettings()
        #expect(other.state.isSidebarOpen)
        #expect(other.state.sidebarTab == .history)
        #expect(other.state.lastExportDirectoryPath == "/tmp/shared")
        #expect(temporary.defaults.object(forKey: "sidebarIsOpen") as? Bool == true)
        #expect(temporary.defaults.string(forKey: "sidebarTab") == "history")
    }

    @Test("AC-7: AppState の作成だけでは何も保存しない")
    func creatingStateWritesNothing() throws {
        let (store, temporary) = try makeStore()
        defer { temporary.remove() }
        _ = AppState(store: store)
        #expect(temporary.defaults.dictionaryRepresentation().isEmpty)
    }

    @Test("AC-7: サイドバーの開閉の変化を観測できる")
    func sidebarOpenIsObservable() throws {
        let (store, temporary) = try makeStore()
        defer { temporary.remove() }
        let state = AppState(store: store)
        let changes = OSAllocatedUnfairLock(initialState: 0)
        withObservationTracking {
            _ = state.isSidebarOpen
        } onChange: {
            changes.withLock { $0 += 1 }
        }
        state.isSidebarOpen = true
        #expect(changes.withLock { $0 } == 1)
    }

    @Test("AC-7: 書き出し先に空文字を入れると、プロパティは空文字のまま保存ではキーを消す")
    func emptyExportDirectoryRemovesKey() throws {
        let (store, temporary) = try makeStore()
        defer { temporary.remove() }
        let state = AppState(store: store)
        state.lastExportDirectoryPath = "/tmp/export"
        #expect(temporary.defaults.string(forKey: "lastExportDirectory") == "/tmp/export")
        state.lastExportDirectoryPath = ""
        #expect(state.lastExportDirectoryPath == "")
        #expect(temporary.defaults.object(forKey: "lastExportDirectory") == nil)
    }
}
