import AppKit
import UniformTypeIdentifiers

/// タイトルバーに出す挿入先の表示の中身。
struct InsertionTargetBadge: Equatable {
    static let label = String(localized: "挿入先")

    let target: InsertionTarget

    /// 挿入先が無ければ nil(何も出さない)。
    static func make(for target: InsertionTarget?) -> InsertionTargetBadge? {
        target.map { InsertionTargetBadge(target: $0) }
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
        if let icon = NSRunningApplication(processIdentifier: target.processIdentifier)?.icon {
            return icon
        }
        let workspace = NSWorkspace.shared
        if let bundleIdentifier = target.bundleIdentifier,
           let url = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return workspace.icon(forFile: url.path)
        }
        return workspace.icon(for: .application)
    }

    private var appName: String? {
        guard let name = target.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty
        else { return nil }
        return name
    }
}
