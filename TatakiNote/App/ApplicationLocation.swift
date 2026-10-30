import Foundation

/// 移す元の扱い。`removable` は元を消して移し、`readOnly` は元を残して写す。
enum ApplicationMoveSource: Equatable {
    case removable
    case readOnly
}

/// アプリがどこから起動されたかの判定。
enum ApplicationLocation {
    /// 「アプリケーション」フォルダの外から起動されたときの、移す元の扱い。中にあれば nil。
    static func moveSource(bundlePath: String, homeDirectory: String, isOnReadOnlyVolume: Bool) -> ApplicationMoveSource? {
        let path = trimmingTrailingSlashes(bundlePath)
        if path.hasPrefix("/Applications/") { return nil }
        let home = trimmingTrailingSlashes(homeDirectory)
        if !home.isEmpty, path.hasPrefix(home + "/Applications/") { return nil }
        if path.contains("/AppTranslocation/") || isOnReadOnlyVolume { return .readOnly }
        return .removable
    }

    /// 移動を聞くか。
    static func shouldAsk(source: ApplicationMoveSource?, isSuppressed: Bool) -> Bool {
        source != nil && !isSuppressed
    }

    private static func trimmingTrailingSlashes(_ path: String) -> String {
        var result = path
        while result.count > 1, result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}

/// 移動の確認で選んだもの。
enum MoveChoice: Equatable {
    case move
    case stay(suppressesFuturePrompts: Bool)
}

/// 選んだ後にすること。
enum MoveStep: Equatable {
    case move
    case terminateOthersThenMove
    case stay(suppressesFuturePrompts: Bool)
}

/// 移動の確認の選び方と、その後の手順。
enum MoveToApplicationsPrompt {
    static func choice(isMoveButton: Bool, isSuppressionChecked: Bool) -> MoveChoice {
        isMoveButton ? .move : .stay(suppressesFuturePrompts: isSuppressionChecked)
    }

    /// 自分以外に動いている同じアプリのプロセス。
    static func otherInstanceIdentifiers(running: [Int32], own: Int32) -> [Int32] {
        var seen = Set<Int32>()
        return running.filter { $0 != own && seen.insert($0).inserted }
    }

    static func step(choice: MoveChoice, otherInstanceIsRunning: Bool) -> MoveStep {
        switch choice {
        case .move:
            return otherInstanceIsRunning ? .terminateOthersThenMove : .move
        case .stay(let suppresses):
            return .stay(suppressesFuturePrompts: suppresses)
        }
    }

    /// 確認の本文。
    static func informativeText(otherInstanceIsRunning: Bool) -> String {
        let base = String(localized: "「アプリケーション」フォルダに置くと、アップデートを入れられます。")
        guard otherInstanceIsRunning else { return base }
        return base + String(localized: "動いている TatakiNote は、移動の前に終了します。")
    }
}
