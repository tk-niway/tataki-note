import AppKit
import Observation

/// 帯の項目に添える注記。
enum StatusItemNote: Equatable {
    case keyNotAssigned
}

/// 設定画面の「エディタ設定」の状態(フォント・文字サイズ・透明度・帯の項目)。
@Observable final class EditorSettingsModel {
    @ObservationIgnored private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// 今のフォントの表示名。システムフォントのときは「システムフォント」。
    var fontDisplayName: String {
        guard let font = settings.resolvedPanelFont else { return String(localized: "システムフォント") }
        return font.displayName ?? font.fontName
    }

    /// 書体を選んでいない(システムフォントを使っている)とき true。
    var isSystemFont: Bool {
        settings.resolvedPanelFont == nil
    }

    /// フォントをシステムフォントに戻す。
    func resetFontToSystem() {
        settings.resetPanelFontToSystem()
    }

    var fontSizeText: String {
        let points = Int(settings.panelFontSize.rounded())
        return String(localized: "\(points) pt")
    }

    var opacityPercentText: String {
        let percent = Int((settings.panelOpacity * 100).rounded())
        return String(localized: "\(percent)%")
    }

    func isStatusItemVisible(_ item: PanelStatusItem) -> Bool {
        !settings.hiddenPanelStatusItems.contains(item)
    }

    func setStatusItem(_ item: PanelStatusItem, isVisible: Bool) {
        settings.setPanelStatusItem(item, isVisible: isVisible)
    }

    func statusItemNote(_ item: PanelStatusItem) -> StatusItemNote? {
        switch item {
        case .commit:
            settings.commitKey == nil ? .keyNotAssigned : nil
        case .commitAndSend:
            settings.commitAndSendKey == nil ? .keyNotAssigned : nil
        case .lineBreak, .close, .characterCount, .lineCount:
            nil
        }
    }
}
