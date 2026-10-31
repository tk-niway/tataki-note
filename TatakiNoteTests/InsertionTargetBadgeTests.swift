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

    @Test("AC-12: 「挿入先なし」の合図の横のずれは、動きを使うなら今の揺れの値、使わないならすべて 0で、数はどちらも6つ")
    func noTargetShakeOffsets() {
        let animated = InsertionTargetBadge.noTargetShakeOffsets(isAnimationEnabled: true)
        let still = InsertionTargetBadge.noTargetShakeOffsets(isAnimationEnabled: false)

        #expect(animated == [-4, 4, -4, 4, -2, 0])
        #expect(still == [0, 0, 0, 0, 0, 0])
        #expect(animated.count == still.count)
    }

    @Test("AC-20: 挿入先なしの文字は「挿入先なし」で、挿入先が無いときはアイコンの表示の中身が作られず、合図のたびに合図の数が1増える")
    func noTargetLabelAndAlertCount() {
        #expect(InsertionTargetBadge.noTargetLabel == "挿入先なし")
        #expect(InsertionTargetBadge.noTargetTipText.isEmpty == false)
        #expect(InsertionTargetBadge.make(for: nil) == nil)

        let model = PanelModel()
        #expect(model.noTargetAlertCount == 0)
        model.signalNoTarget()
        #expect(model.noTargetAlertCount == 1)
        model.signalNoTarget()
        #expect(model.noTargetAlertCount == 2)
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

    @Test("AC-14: 待ちの間は、挿入先があってもなくても、挿入先もアイコンも出さず待ちになる")
    func pendingHidesTargetAndNoTarget() {
        let safari = target(name: "Safari")

        #expect(InsertionTargetBadge.display(target: nil, isPending: true) == .pending)
        #expect(InsertionTargetBadge.display(target: safari, isPending: true) == .pending)
    }

    @Test("AC-14: 待ちが終われば、挿入先があればアイコン、無ければ「挿入先なし」になる")
    func settledShowsTargetOrNoTarget() throws {
        let safari = target(name: "Safari")

        let withTarget = InsertionTargetBadge.display(target: safari, isPending: false)
        let withoutTarget = InsertionTargetBadge.display(target: nil, isPending: false)

        #expect(withTarget == .target(try #require(InsertionTargetBadge.make(for: safari))))
        #expect(withoutTarget == .noTarget)
    }

    @Test("AC-14: 「挿入先なし」の部品は、待ちの間も見えない形で置かれ、挿入先があるときは置かれない")
    func noTargetLabelIsPlacedWhilePending() throws {
        let badge = try #require(InsertionTargetBadge.make(for: target(name: "Safari")))

        #expect(InsertionTargetDisplay.pending.placesNoTargetLabel)
        #expect(InsertionTargetDisplay.noTarget.placesNoTargetLabel)
        #expect(!InsertionTargetDisplay.target(badge).placesNoTargetLabel)
    }

    @Test("AC-14: 「挿入先なし」は、待ちの間は見せず読み上げず、「挿入先なし」のときだけ見せる")
    func noTargetLabelIsVisibleOnlyWhenNoTarget() throws {
        let badge = try #require(InsertionTargetBadge.make(for: target(name: "Safari")))

        #expect(!InsertionTargetDisplay.pending.isNoTargetLabelVisible)
        #expect(!InsertionTargetDisplay.target(badge).isNoTargetLabelVisible)
        #expect(InsertionTargetDisplay.noTarget.isNoTargetLabelVisible)
        #expect(InsertionTargetBadge.pendingAccessibilityLabel == "挿入先を調べています")
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
