import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
private final class CallLog {
    private(set) var entries: [String] = []

    func append(_ entry: String) {
        entries.append(entry)
    }
}

@MainActor
struct UpdateBadgeTests {
    private func withBadge(
        _ body: (UpdateModel, UpdateBadgeController, CallLog, AppSettings) async throws -> Void
    ) async throws {
        let temporary = try TemporaryDefaults()
        defer { temporary.remove() }
        let settings = temporary.makeSettings()
        let model = UpdateModel(settings: settings, updater: RecordingUpdater())
        let log = CallLog()
        let badge = UpdateBadgeController(updates: model, setBadgeLabel: { log.append("badge:\($0 ?? "")") })
        try await body(model, badge, log, settings)
    }

    @Test("AC-9: 始めたときに今の状態を当てる。新しい版が無ければ印は付けない")
    func startAppliesNoBadgeWhenNothingPending() async throws {
        try await withBadge { _, badge, log, _ in
            badge.start()

            #expect(log.entries == ["badge:"])
        }
    }

    @Test("AC-9: 新しい版が見つかると印が付き、見たら消える")
    func badgeFollowsPendingUpdate() async throws {
        try await withBadge { model, badge, log, _ in
            badge.start()

            model.handle(.foundInBackground(version: "1.3.0"))
            await yieldUntil { log.entries.count == 2 }
            model.handle(.userAttended)
            await yieldUntil { log.entries.count == 3 }

            #expect(log.entries == ["badge:", "badge:1", "badge:"])
        }
    }

    @Test("AC-9: 新しい版があるまま始めると、最初から印が付く")
    func startAppliesBadgeWhenAlreadyPending() async throws {
        try await withBadge { model, badge, log, _ in
            model.handle(.foundInBackground(version: "1.3.0"))

            badge.start()

            #expect(log.entries == ["badge:1"])
        }
    }

    @Test("AC-9: 新しい版の有無が変わらない出来事では付け直さない")
    func unrelatedEventsDoNotReapply() async throws {
        try await withBadge { model, badge, log, _ in
            badge.start()

            model.handle(.checkCompleted)
            model.handle(.checkFailed)
            try await Task.sleep(for: .milliseconds(100))

            #expect(log.entries == ["badge:"])
        }
    }

    @Test("AC-9: reapply で今の状態の印を付け直す(Dock のアイコンの出し入れで消えた場合)")
    func reapplyPutsBadgeBack() async throws {
        try await withBadge { model, badge, log, _ in
            badge.start()
            model.handle(.foundInBackground(version: "1.3.0"))
            await yieldUntil { log.entries.count == 2 }

            badge.reapply()

            #expect(log.entries == ["badge:", "badge:1", "badge:1"])
        }
    }

    @Test("AC-9: 始めるのを2回呼んでも、見張りは1つだけ")
    func startingTwiceObservesOnce() async throws {
        try await withBadge { model, badge, log, _ in
            badge.start()
            badge.start()

            model.handle(.foundInBackground(version: "1.3.0"))
            await yieldUntil { log.entries.count == 2 }
            try await Task.sleep(for: .milliseconds(100))

            #expect(log.entries == ["badge:", "badge:1"])
        }
    }

    @Test("AC-9: 「Dock にアイコンを表示」を切り替えたときは、アクティベーションポリシーを替えた後に印を付け直す")
    func dockIconControllerCallsDidApplyPolicyAfterPolicy() async throws {
        let temporary = try TemporaryDefaults()
        defer { temporary.remove() }
        let settings = temporary.makeSettings()
        settings.showsDockIcon = true
        let model = UpdateModel(settings: settings, updater: RecordingUpdater())
        model.handle(.foundInBackground(version: "1.3.0"))
        let log = CallLog()
        let badge = UpdateBadgeController(updates: model, setBadgeLabel: { log.append("badge:\($0 ?? "")") })
        let dock = DockIconController(
            settings: settings,
            setActivationPolicy: { log.append("policy:\($0.rawValue)") },
            didApplyPolicy: { badge.reapply() }
        )

        dock.start()
        settings.showsDockIcon = false
        await yieldUntil { log.entries.count == 4 }
        settings.showsDockIcon = true
        await yieldUntil { log.entries.count == 6 }

        let regular = NSApplication.ActivationPolicy.regular.rawValue
        let accessory = NSApplication.ActivationPolicy.accessory.rawValue
        #expect(log.entries == [
            "policy:\(regular)", "badge:1",
            "policy:\(accessory)", "badge:1",
            "policy:\(regular)", "badge:1",
        ])
    }

    @Test("AC-9: 同じ値を書いてポリシーを替えないときは、印を付け直さない")
    func sameDockSettingDoesNotReapplyBadge() async throws {
        let temporary = try TemporaryDefaults()
        defer { temporary.remove() }
        let settings = temporary.makeSettings()
        settings.showsDockIcon = true
        let log = CallLog()
        let dock = DockIconController(
            settings: settings,
            setActivationPolicy: { _ in log.append("policy") },
            didApplyPolicy: { log.append("applied") }
        )

        dock.start()
        settings.showsDockIcon = true
        try await Task.sleep(for: .milliseconds(100))

        #expect(log.entries == ["policy", "applied"])
    }
}
