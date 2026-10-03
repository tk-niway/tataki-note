/// 起動したときに出すもの。
enum LaunchPresentation: Equatable {
    case nothing
    case tutorial
    case permissionGuide(PermissionGuideReason)
}

/// 起動したときに出すものの判定。
enum FirstLaunchFlow {
    /// 表示済みかどうかと許可の有無から、出すものを決める。
    static func presentation(hasShownTutorial: Bool, isTrusted: Bool) -> LaunchPresentation {
        switch (hasShownTutorial, isTrusted) {
        case (false, true): .tutorial
        case (false, false): .permissionGuide(.firstLaunch)
        case (true, true): .nothing
        case (true, false): .permissionGuide(.launch)
        }
    }

    /// 起動したときに出すものを決め、抑止されていなければ表示済みを保存する。
    static func resolveOnLaunch(settings: AppSettings, isTrusted: Bool, isSuppressed: Bool) -> LaunchPresentation {
        let result = presentation(
            hasShownTutorial: settings.hasShownFirstLaunchTutorial || isSuppressed,
            isTrusted: isTrusted
        )
        if !isSuppressed {
            settings.hasShownFirstLaunchTutorial = true
        }
        return result
    }
}
