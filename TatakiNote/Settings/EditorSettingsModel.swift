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
        String(localized: "改行のあとに足す間隔を、行の高さを単位に決めます。折り返しただけの行の間には足しません。")
    }

    var letterSpacingText: String {
        let percent = EditorReadability.clampedLetterSpacingPercent(settings.editorLetterSpacingPercent)
        return String(localized: "\(percent)%")
    }

    /// 「字間」の下に出す説明文。
    static var letterSpacingDescription: String {
        String(localized: "文字と文字の間に足す幅を、文字サイズに対する割合で決めます。")
    }

    var maxLineLengthText: String {
        guard let length = EditorReadability.clampedMaxLineLength(settings.editorMaxLineLength) else {
            return String(localized: "上限なし")
        }
        return String(localized: "\(length) 文字")
    }

    /// 「1行の長さの上限」の下に出す説明文。
    static var maxLineLengthDescription: String {
        String(localized: "1行に入る全角の文字数の上限です。入力欄のほうが広いときは、文章を中央に寄せます。")
    }

    /// 1行の長さの上限を1つ上げる。上限なしより先には進まない。
    func incrementMaxLineLength() {
        settings.editorMaxLineLength = EditorReadability.nextMaxLineLength(after: settings.editorMaxLineLength)
    }

    /// 1行の長さの上限を1つ下げる。下の端で止まる。
    func decrementMaxLineLength() {
        settings.editorMaxLineLength = EditorReadability.previousMaxLineLength(before: settings.editorMaxLineLength)
    }

    /// 「折り返した行の字下げ」の下に出す説明文。
    static var wrapIndentDescription: String {
        String(localized: "字下げや箇条書きの行が折り返したとき、続きの行の左端を本文の始まりに揃えます。")
    }

    var caretWidthText: String {
        let width = EditorReadability.clampedCaretWidth(settings.editorCaretWidth)
        return String(localized: "\(width) pt")
    }

    /// 「カーソルの太さ」の下に出す説明文。
    static var caretWidthDescription: String {
        String(localized: "「縦線」のときの線の太さです。")
    }

    /// カーソルの太さを変えられるとき true。形が「縦線」のときだけ。
    var isCaretWidthEnabled: Bool {
        settings.editorCaretShape == .bar
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
