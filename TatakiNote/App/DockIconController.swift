import AppKit

/// 設定に合わせて Dock のアイコンを出し入れする。
final class DockIconController {
    private let settings: AppSettings
    private let setActivationPolicy: (NSApplication.ActivationPolicy) -> Void
    private let didHideIcon: () -> Void
    private let didApplyPolicy: () -> Void
    private var appliedShowsIcon: Bool?
    private var isStarted = false

    init(
        settings: AppSettings,
        setActivationPolicy: @escaping (NSApplication.ActivationPolicy) -> Void,
        didHideIcon: @escaping () -> Void = {},
        didApplyPolicy: @escaping () -> Void = {}
    ) {
        self.settings = settings
        self.setActivationPolicy = setActivationPolicy
        self.didHideIcon = didHideIcon
        self.didApplyPolicy = didApplyPolicy
    }

    /// 設定の値に合うアクティベーションポリシー。出すなら `.regular`、出さないなら `.accessory`。
    static func activationPolicy(showsDockIcon: Bool) -> NSApplication.ActivationPolicy {
        showsDockIcon ? .regular : .accessory
    }

    /// 今の設定を当て、設定が変わるたびに当て直す。
    func start() {
        guard !isStarted else { return }
        isStarted = true
        apply(settings.showsDockIcon)
        observeRepeatedly(
            tracking: { [weak self] in
                _ = self?.settings.showsDockIcon
            },
            onChange: { [weak self] in
                guard let self else { return false }
                self.apply(self.settings.showsDockIcon)
                return true
            }
        )
    }

    private func apply(_ showsDockIcon: Bool) {
        guard appliedShowsIcon != showsDockIcon else { return }
        let isFirstApply = appliedShowsIcon == nil
        appliedShowsIcon = showsDockIcon
        setActivationPolicy(Self.activationPolicy(showsDockIcon: showsDockIcon))
        didApplyPolicy()
        if !showsDockIcon && !isFirstApply {
            didHideIcon()
        }
    }
}
