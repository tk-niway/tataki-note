import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct AppInfoModelTests {
    private func makeModel(_ infoDictionary: [String: Any]) -> AppInfoModel {
        AppInfoModel(
            infoDictionary: infoDictionary,
            permissionStatus: PermissionGuideModel(permission: OverriddenAccessibilityPermission(isTrusted: true))
        )
    }

    // MARK: - バージョン

    @Test("AC-43: バージョン番号とビルド番号を Info.plist の値から読み、無い・空・文字列でないなら読めない(nil)")
    func readsVersionAndBuild() {
        let model = makeModel(["CFBundleShortVersionString": "1.2", "CFBundleVersion": "34"])
        #expect(model.version == "1.2")
        #expect(model.build == "34")

        let missing = makeModel([:])
        #expect(missing.version == nil)
        #expect(missing.build == nil)

        let empty = makeModel(["CFBundleShortVersionString": "", "CFBundleVersion": ""])
        #expect(empty.version == nil)
        #expect(empty.build == nil)

        let numbers = makeModel(["CFBundleShortVersionString": 1.2, "CFBundleVersion": 34])
        #expect(numbers.version == nil)
        #expect(numbers.build == nil)
    }

    @Test("AC-43: 表示は「版 (ビルド)」で、読めない側は「不明」、両方読めなければ「不明」だけ")
    func versionText() {
        let unknown = String(localized: "不明")

        #expect(makeModel(["CFBundleShortVersionString": "1.2", "CFBundleVersion": "34"]).versionText == "1.2 (34)")
        #expect(makeModel(["CFBundleVersion": "34"]).versionText == "\(unknown) (34)")
        #expect(makeModel(["CFBundleShortVersionString": "1.2"]).versionText == "1.2 (\(unknown))")
        #expect(makeModel([:]).versionText == unknown)
    }

    // MARK: - 叩いたときの言葉

    @Test("AC-44: 叩くたびに「トン」「タン」「カタッ」「ターン!」の順で選ばれ、5回目から「トン」に戻る")
    func tapWordsCycleInOrder() {
        #expect(AppInfoModel.tapWords == ["トン", "タン", "カタッ", "ターン!"])
        let words = (0..<9).map { AppInfoModel.tapWord(at: $0) }
        #expect(words == ["トン", "タン", "カタッ", "ターン!", "トン", "タン", "カタッ", "ターン!", "トン"])
    }

    @Test("AC-44: 叩いた回数が負なら先頭の「トン」として扱う")
    func negativeTapIndexIsTreatedAsZero() {
        #expect(AppInfoModel.tapWord(at: -1) == "トン")
        #expect(AppInfoModel.tapWord(at: -100) == "トン")
    }

    // MARK: - 許可のバッジ

    @Test("AC-45: 許可があれば「許可されています」、無ければ「許可されていません」のバッジの文言")
    func permissionBadgeText() {
        let trusted = AppInfoModel(
            infoDictionary: [:],
            permissionStatus: PermissionGuideModel(permission: PermissionStub(isTrusted: true))
        )
        let untrusted = AppInfoModel(
            infoDictionary: [:],
            permissionStatus: PermissionGuideModel(permission: PermissionStub(isTrusted: false))
        )
        #expect(trusted.permissionBadgeText == "許可されています")
        #expect(untrusted.permissionBadgeText == "許可されていません")
    }

    @Test("AC-45: 表示している間に許可が変わると、バッジの文言も変わる")
    func permissionBadgeTextFollowsPermission() {
        let permission = PermissionStub(isTrusted: false)
        let model = AppInfoModel(
            infoDictionary: [:],
            permissionStatus: PermissionGuideModel(permission: permission)
        )
        #expect(model.permissionBadgeText == "許可されていません")

        permission.isTrusted = true
        model.permissionStatus.refresh()

        #expect(model.permissionBadgeText == "許可されています")
    }

    // MARK: - 許可の状態

    @Test("AC-10: 表示している間に許可が変わると、開き直さなくても確かめ直しで変わり、取り消すと確かめ直しをやめる")
    func watchPermissionFollowsChangesUntilCancelled() async throws {
        let permission = PermissionStub(isTrusted: false)
        let model = AppInfoModel(
            infoDictionary: [:],
            permissionStatus: PermissionGuideModel(permission: permission, opener: SettingsOpenerStub())
        )
        #expect(!model.permissionStatus.isTrusted)

        let watching = Task { await model.watchPermission(interval: .milliseconds(10)) }

        permission.isTrusted = true
        #expect(try await waitUntil(attempts: 200, interval: .milliseconds(10)) { model.permissionStatus.isTrusted })
        permission.isTrusted = false
        #expect(try await waitUntil(attempts: 200, interval: .milliseconds(10)) { !model.permissionStatus.isTrusted })

        watching.cancel()
        await watching.value

        permission.isTrusted = true
        try await Task.sleep(for: .milliseconds(100))
        #expect(!model.permissionStatus.isTrusted)
    }

    @Test("AC-11: 「システム設定を開く」は、許可が無ければシステムのダイアログを求めてからアクセシビリティの設定を開く")
    func openSystemSettingsRequestsPromptFirst() {
        let log = PermissionCallLog()
        let model = AppInfoModel(
            infoDictionary: [:],
            permissionStatus: PermissionGuideModel(
                permission: PermissionStub(isTrusted: false, log: log),
                opener: SettingsOpenerStub(log: log)
            )
        )

        model.permissionStatus.openSystemSettings()

        #expect(log.calls == ["prompt", "open"])
    }

    @Test("AC-11: 「システム設定を開く」は、許可があればダイアログを求めずにアクセシビリティの設定を開く")
    func openSystemSettingsSkipsPromptWhenTrusted() {
        let log = PermissionCallLog()
        let model = AppInfoModel(
            infoDictionary: [:],
            permissionStatus: PermissionGuideModel(
                permission: PermissionStub(isTrusted: true, log: log),
                opener: SettingsOpenerStub(log: log)
            )
        )

        model.permissionStatus.openSystemSettings()

        #expect(log.calls == ["open"])
    }
}
