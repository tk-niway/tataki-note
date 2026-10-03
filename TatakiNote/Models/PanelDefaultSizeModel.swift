import CoreGraphics
import Foundation
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

    /// 「パネルの既定の大きさ」の下に出す、値の範囲の説明文。
    static var rangeDescription: String {
        rangeDescription(widthRange: widthRange, heightRange: heightRange)
    }

    /// 範囲を指定して作る、値の範囲の説明文。
    static func rangeDescription(widthRange: ClosedRange<Int>, heightRange: ClosedRange<Int>) -> String {
        let minWidth = String(widthRange.lowerBound)
        let maxWidth = String(widthRange.upperBound)
        let minHeight = String(heightRange.lowerBound)
        let maxHeight = String(heightRange.upperBound)
        return String(localized: "パネルを開いたときの大きさです(幅 \(minWidth)〜\(maxWidth)・高さ \(minHeight)〜\(maxHeight) pt)。変えると、次にパネルを開いたときから使います。")
    }

    /// 「パネルの既定の大きさ」の下に出す、ドラッグで決めた大きさの説明文。
    static var heldSizeDescription: String {
        String(localized: "パネルの端をドラッグして大きさを変えると、文章を挿入するまではその大きさで開きます(その間は、ここを変えてもパネルの大きさは変わりません)。「今のパネルの大きさを既定にする」は、ドラッグで大きさを変えた後に押せて、ドラッグで決めた大きさを既定にします。")
    }

    private static func integerRange(_ range: ClosedRange<Double>) -> ClosedRange<Int> {
        Int(range.lowerBound.rounded(.up))...Int(range.upperBound.rounded(.down))
    }
}
