import AppKit
import UniformTypeIdentifiers

/// タイトルバーの挿入先の表示の状態。
enum InsertionTargetDisplay: Equatable {
    /// 開くときの調べの答えを待っている。挿入先も「挿入先なし」も出さない。
    case pending
    case target(InsertionTargetBadge)
    case noTarget
}

extension InsertionTargetDisplay {
    /// 「挿入先なし」の部品を置くか(待ちの間も、見えない形で置く)。
    var placesNoTargetLabel: Bool {
        switch self {
        case .pending, .noTarget: true
        case .target: false
        }
    }

    /// 「挿入先なし」を見せ、読み上げるか。
    var isNoTargetLabelVisible: Bool {
        self == .noTarget
    }

    /// 読み上げのラベル。
    var accessibilityLabel: String {
        switch self {
        case .pending: InsertionTargetBadge.pendingAccessibilityLabel
        case .target(let badge): badge.accessibilityLabel
        case .noTarget: InsertionTargetBadge.noTargetLabel
        }
    }

    /// アクセシビリティの識別子。
    var accessibilityIdentifier: String {
        switch self {
        case .pending: "promptPanel.insertionTargetPending"
        case .target: "promptPanel.insertionTarget"
        case .noTarget: "promptPanel.noInsertionTarget"
        }
    }
}

/// タイトルバーに出す挿入先の表示の中身。
struct InsertionTargetBadge: Equatable {
    static let label = String(localized: "挿入先")
    static let noTargetLabel = String(localized: "挿入先なし")
    static let pendingAccessibilityLabel = String(localized: "挿入先を調べています")

    let target: InsertionTarget

    /// 挿入先と待ちの印から、出すものを決める。
    static func display(target: InsertionTarget?, isPending: Bool) -> InsertionTargetDisplay {
        if isPending { return .pending }
        if let badge = make(for: target) { return .target(badge) }
        return .noTarget
    }

    /// 挿入先が無ければ nil(何も出さない)。
    static func make(for target: InsertionTarget?) -> InsertionTargetBadge? {
        target.map { InsertionTargetBadge(target: $0) }
    }

    /// 「挿入先なし」の合図で、横にずらす量を順に並べたもの。動きを使わないときはすべて 0。
    static func noTargetShakeOffsets(isAnimationEnabled: Bool) -> [CGFloat] {
        isAnimationEnabled ? [-4, 4, -4, 4, -2, 0] : [0, 0, 0, 0, 0, 0]
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
