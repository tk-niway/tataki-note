import AppKit
import UniformTypeIdentifiers

/// タイトルバーに出す挿入先の表示の中身。
struct InsertionTargetBadge: Equatable {
    static let label = String(localized: "挿入先")
    static let noTargetLabel = String(localized: "挿入先なし")
    static let noTargetTipText = String(localized: "このまま確定しても挿入しません。入れたい入力欄をクリックすると、そこが挿入先になります")

    let target: InsertionTarget

    /// 挿入先が無ければ nil(何も出さない)。
    static func make(for target: InsertionTarget?) -> InsertionTargetBadge? {
        target.map { InsertionTargetBadge(target: $0) }
    }

    /// 「挿入先なし」の合図で、横にずらす量を順に並べたもの。動きを使わないときはすべて 0。
    static func noTargetShakeOffsets(isAnimationEnabled: Bool) -> [CGFloat] {
        isAnimationEnabled ? [-4, 4, -4, 4, -2, 0] : [0, 0, 0, 0, 0, 0]
    }

    /// アイコンにマウスを乗せたときのチップの文。
    var tipText: String {
        if let name = appName {
            return String(localized: "\(name) に挿入します")
        }
        return String(localized: "パネルを開いたときに使っていたアプリに挿入します")
    }

    var accessibilityLabel: String {
        if let name = appName {
            return String(localized: "挿入先: \(name)")
        }
        return String(localized: "挿入先: パネルを開いたときに使っていたアプリ")
    }

    /// 挿入先のアプリのアイコン。取れなければ汎用のアプリのアイコン。
    static func systemIcon(for target: InsertionTarget) -> NSImage {
        icon(for: target, genericIcon: NSWorkspace.shared.icon(for: .application))
    }

    /// 動いているアプリ、入っているアプリの順にアイコンを探し、どちらも無ければ `genericIcon`。
    static func icon(for target: InsertionTarget, genericIcon: @autoclosure () -> NSImage) -> NSImage {
        runningApplicationIcon(for: target) ?? installedApplicationIcon(for: target) ?? genericIcon()
    }

    private static func runningApplicationIcon(for target: InsertionTarget) -> NSImage? {
        NSRunningApplication(processIdentifier: target.processIdentifier)?.icon
    }

    private static func installedApplicationIcon(for target: InsertionTarget) -> NSImage? {
        let workspace = NSWorkspace.shared
        guard let bundleIdentifier = target.bundleIdentifier,
              let url = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else { return nil }
        return workspace.icon(forFile: url.path)
    }

    private var appName: String? {
        guard let name = target.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty
        else { return nil }
        return name
    }
}
