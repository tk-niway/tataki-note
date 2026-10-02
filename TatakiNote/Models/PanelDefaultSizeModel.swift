import CoreGraphics
import Observation

/// 設定画面の「パネルの既定の大きさ」の状態(幅と高さの値と、2つのボタン)。
@Observable final class PanelDefaultSizeModel {
    static let initialSize: CGSize = PanelMetrics.defaultSize
    static let widthRange: ClosedRange<Int> = integerRange(PanelMetrics.defaultWidthRange)
    static let heightRange: ClosedRange<Int> = integerRange(PanelMetrics.defaultHeightRange)
    static let step = 10

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let currentPanelSize: () -> CGSize?

    init(settings: AppSettings, currentPanelSize: @escaping () -> CGSize?) {
        self.settings = settings
        self.currentPanelSize = currentPanelSize
    }


    var width: Int {
        get { Int(settings.panelDefaultWidth.rounded()) }
        set { settings.panelDefaultWidth = Double(newValue) }
    }

    var height: Int {
        get { Int(settings.panelDefaultHeight.rounded()) }
        set { settings.panelDefaultHeight = Double(newValue) }
    }

    var canUseCurrentPanelSize: Bool {
        currentPanelSize() != nil
    }

    func useCurrentPanelSize() {
        guard let size = currentPanelSize() else { return }
        settings.panelDefaultWidth = Double(size.width).rounded()
        settings.panelDefaultHeight = Double(size.height).rounded()
    }

    func resetToInitial() {
        width = Int(Self.initialSize.width)
        height = Int(Self.initialSize.height)
    }

    private static func integerRange(_ range: ClosedRange<Double>) -> ClosedRange<Int> {
        Int(range.lowerBound.rounded(.up))...Int(range.upperBound.rounded(.down))
    }
}
