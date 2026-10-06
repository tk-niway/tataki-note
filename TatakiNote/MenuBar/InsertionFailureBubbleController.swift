import AppKit

/// 吹き出しの出どころ(メニューバーのアイコン)を探す。
protocol StatusItemAnchorLocating {
    func locateAnchor() -> NSView?
}

/// 吹き出しを出す・閉じる。
protocol InsertionFailureBubblePresenting: AnyObject {
    var onClick: (() -> Void)? { get set }
    var onOutsideClick: (() -> Void)? { get set }
    var onClosedBySystem: (() -> Void)? { get set }
    func show(message: String, relativeTo anchor: NSView)
    func close()
}

/// 挿入できなかったことを、メニューバーのアイコンから出す吹き出しで知らせる。
final class InsertionFailureBubbleController: InsertionFailureNotifying {
    static let anchorSearchInterval: Duration = .milliseconds(50)
    static let anchorSearchAttempts = 20

    private let model: InsertionFailureBubbleModel
    private let locator: StatusItemAnchorLocating
    private let presenter: InsertionFailureBubblePresenting
    private let sleep: (Duration) async -> Void
    private let onOpenPanel: () -> Void

    private(set) var pendingDismissal: Task<Void, Never>?

    init(
        model: InsertionFailureBubbleModel,
        locator: StatusItemAnchorLocating,
        presenter: InsertionFailureBubblePresenting,
        sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        onOpenPanel: @escaping () -> Void
    ) {
        self.model = model
        self.locator = locator
        self.presenter = presenter
        self.sleep = sleep
        self.onOpenPanel = onOpenPanel
        presenter.onClick = { [weak self] in
            self?.dismiss()
            self?.onOpenPanel()
        }
        presenter.onOutsideClick = { [weak self] in self?.dismiss() }
        presenter.onClosedBySystem = { [weak self] in self?.dismiss() }
    }

    /// 吹き出しを出して、5秒後に閉じる準備をする。5秒は待たずに返る。
    func notify(_ notice: InsertionFailureNotice) async {
        let id = model.present()
        var anchor = locator.locateAnchor()
        var attempts = 0
        while anchor == nil && attempts < Self.anchorSearchAttempts {
            await sleep(Self.anchorSearchInterval)
            guard model.presentationID == id, model.isPresented else { return }
            attempts += 1
            anchor = locator.locateAnchor()
        }
        guard let anchor else {
            dismiss()
            return
        }
        presenter.show(message: InsertionFailureBubbleModel.message, relativeTo: anchor)
        pendingDismissal?.cancel()
        let sleep = self.sleep
        pendingDismissal = Task { [weak self] in
            await sleep(InsertionFailureBubbleModel.displayDuration)
            self?.expire(id)
        }
    }

    /// 吹き出しを閉じ、一時的に出したアイコンを戻す。
    func dismiss() {
        pendingDismissal?.cancel()
        presenter.close()
        model.dismiss()
    }

    /// アイコンの出し入れが書き戻されたときに設定へ反映し、必要なら吹き出しを閉じる。
    func menuBarIconInsertionDidChange(to isInserted: Bool, settings: AppSettings) {
        if model.menuBarIconInsertionDidChange(to: isInserted, settings: settings) {
            dismiss()
        }
    }

    private func expire(_ id: Int) {
        guard !Task.isCancelled, model.presentationID == id, model.isPresented else { return }
        dismiss()
    }
}
