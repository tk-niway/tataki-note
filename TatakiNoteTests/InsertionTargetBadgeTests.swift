import AppKit
import Testing
import UniformTypeIdentifiers
@testable import TatakiNote

@MainActor
struct InsertionTargetBadgeTests {
    private func target(name: String?, bundleIdentifier: String? = nil) -> InsertionTarget {
        InsertionTarget(processIdentifier: 99_999_999, bundleIdentifier: bundleIdentifier, localizedName: name)
    }

    @Test("AC-44: 挿入先があるときは表示の中身ができ、「挿入先」の文字と挿入先を持つ")
    func badgeExistsForTarget() throws {
        let safari = target(name: "Safari", bundleIdentifier: "com.apple.Safari")

        let badge = try #require(InsertionTargetBadge.make(for: safari))

        #expect(badge.target == safari)
        #expect(InsertionTargetBadge.label == "挿入先")
    }

    @Test("AC-44: 挿入先が無いときは何も出さない")
    func noBadgeWithoutTarget() {
        #expect(InsertionTargetBadge.make(for: nil) == nil)
    }

    @Test("AC-44: チップの文は「<アプリ名> に挿入します」、アクセシビリティのラベルは「挿入先: <アプリ名>」")
    func textsNameTheApp() throws {
        let badge = try #require(InsertionTargetBadge.make(for: target(name: "Safari")))

        #expect(badge.tipText == "Safari に挿入します")
        #expect(badge.accessibilityLabel == "挿入先: Safari")
    }

    @Test("AC-44: アプリ名の前後の空白は除いて出す")
    func nameIsTrimmed() throws {
        let badge = try #require(InsertionTargetBadge.make(for: target(name: "  Safari \n")))

        #expect(badge.tipText == "Safari に挿入します")
        #expect(badge.accessibilityLabel == "挿入先: Safari")
    }

    @Test("AC-44: アプリ名が無い・空・空白だけのときは、パネルを開いたときに使っていたアプリと言う", arguments: [nil, "", "   "])
    func textsWithoutName(name: String?) throws {
        let badge = try #require(InsertionTargetBadge.make(for: target(name: name)))

        #expect(badge.tipText == "パネルを開いたときに使っていたアプリに挿入します")
        #expect(badge.accessibilityLabel == "挿入先: パネルを開いたときに使っていたアプリ")
    }

    @Test("AC-44: チュートリアルの練習のように TatakiNote 自身が挿入先でも、そのアプリ名で出す")
    func ownAppIsShownAsIs() throws {
        let own = InsertionTarget(
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            bundleIdentifier: nil,
            localizedName: "TatakiNote"
        )

        let badge = try #require(InsertionTargetBadge.make(for: own))

        #expect(badge.tipText == "TatakiNote に挿入します")
    }

    @Test("AC-44: アイコンが取れない挿入先(存在しない pid と bundle ID)では、汎用のアプリのアイコンになる")
    func missingIconFallsBackToGenericApplicationIcon() throws {
        let missing = target(name: "Missing", bundleIdentifier: "invalid.tatakinote.nonexistent")

        let generic = NSImage(size: NSSize(width: 16, height: 16))

        let icon = InsertionTargetBadge.icon(for: missing, genericIcon: generic)

        #expect(icon === generic)
        #expect(InsertionTargetBadge.systemIcon(for: missing).size.width > 0)
    }
}
