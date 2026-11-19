import AppKit
import Observation

/// 帯の項目に添える注記。
enum StatusItemNote: Equatable {
    case keyNotAssigned
}

/// 設定画面の「パネル」の状態(フォント・文字サイズ・透明度・帯の項目)。
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

    var bottomPaddingText: String {
        let lines = settings.editorBottomPaddingLines
        return String(localized: "\(lines) 行")
    }

    /// 「最終行の下の余白」の下に出す説明文。
    static var bottomPaddingDescription: String {
        String(localized: "入力欄の最後の行の下に空ける行数です。0 にすると余白なしになります。")
    }

    private static let fixedLocale = Locale(identifier: "en_US_POSIX")

    var lineHeightText: String {
        let value = EditorReadability.clampedLineHeightMultiple(settings.editorLineHeightMultiple)
        return String(localized: "\(value.formatted(.number.precision(.fractionLength(1)).grouping(.never).locale(Self.fixedLocale))) 倍")
    }

    var paragraphSpacingText: String {
        let value = EditorReadability.clampedParagraphSpacingLines(settings.editorParagraphSpacingLines)
        let text = value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(Self.fixedLocale))
        return String(localized: "\(text) 行")
    }

    /// 「段落の間隔」の下に出す説明文。
    static var paragraphSpacingDescription: String {
        String(localized: "改行のあとに空ける間隔")
    }

    var letterSpacingText: String {
        let percent = EditorReadability.clampedLetterSpacingPercent(settings.editorLetterSpacingPercent)
        return String(localized: "\(percent)%")
    }

    /// 「字間」の下に出す説明文。
    static var letterSpacingDescription: String {
        String(localized: "文字と文字の間の幅")
    }

    /// 「折り返した行の字下げ」の下に出す説明文。
    static var wrapIndentDescription: String {
        String(localized: "続きの行を本文の始まりに揃えます")
    }

    /// 「URL を畳む」の下に出す説明文。
    static var foldURLsDescription: String {
        String(localized: "長い URL を短くし、色を変えて表示します。⌘ クリックで開きます")
    }

    /// フォント名を描くフォント。システムフォントのときはシステムフォント、書体を選んでいるときはその書体(12pt)。
    var fontNameFont: NSFont {
        guard let font = settings.resolvedPanelFont else { return .systemFont(ofSize: Self.fontNameSize) }
        return NSFont(descriptor: font.fontDescriptor, size: Self.fontNameSize) ?? .systemFont(ofSize: Self.fontNameSize)
    }

    static let fontNameSize: CGFloat = 12

    /// 「透明度」の下に出す説明文。
    static var opacityDescription: String {
        String(localized: "パネル背景の透明度")
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
