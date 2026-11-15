import CoreGraphics
import Foundation

/// 入力欄のカーソルの形・位置・点滅の計算。
enum EditorCaretGeometry {
    /// 下線の太さ。
    static let underlineThickness: CGFloat = 2

    /// ブロックの塗りの濃さ。
    static let blockFillAlpha: CGFloat = 0.35

    /// 同じ行とみなす、上端の差の上限。
    static let sameLineTolerance: CGFloat = 1

    /// システムのカーソルのまま描くか。縦線で太さが 1 のときだけ。
    static func usesSystemCaret(shape: EditorCaretShape, width: Int) -> Bool {
        shape == .bar && width == 1
    }

    /// 自前のカーソルを点滅させる条件。窓がキーで、入力欄にフォーカスがあり、何も選択していないとき。
    static func isCaretActive(isKeyWindow: Bool, isFirstResponder: Bool, selectionLength: Int) -> Bool {
        isKeyWindow && isFirstResponder && selectionLength == 0
    }

    /// 描く矩形(入力欄の座標、上が小さい y)。
    static func rect(
        shape: EditorCaretShape,
        barWidth: CGFloat,
        caretRect: CGRect,
        textHeight: CGFloat,
        characterRect: CGRect?,
        fallbackWidth: CGFloat
    ) -> CGRect {
        let characterWidth = width(of: characterRect, caretRect: caretRect, fallbackWidth: fallbackWidth)
        switch shape {
        case .bar:
            return CGRect(
                x: caretRect.minX,
                y: caretRect.minY,
                width: barWidth,
                height: min(caretRect.height, textHeight)
            )
        case .block:
            return CGRect(x: caretRect.minX, y: caretRect.minY, width: characterWidth, height: textHeight)
        case .underline:
            return CGRect(
                x: caretRect.minX,
                y: caretRect.minY + textHeight - underlineThickness,
                width: characterWidth,
                height: underlineThickness
            )
        }
    }

    /// 枠が返らない位置(空の文書・末尾の改行の後)のカーソルの枠。
    static func fallbackCaretRect(
        previousLineMaxY: CGFloat?,
        containerOrigin: CGPoint,
        lineFragmentPadding: CGFloat,
        textHeight: CGFloat,
        lineSpacing: CGFloat,
        paragraphSpacing: CGFloat
    ) -> CGRect {
        let top = previousLineMaxY.map { $0 + lineSpacing + paragraphSpacing } ?? containerOrigin.y
        return CGRect(x: containerOrigin.x + lineFragmentPadding, y: top, width: 0, height: textHeight)
    }

    private static func width(of characterRect: CGRect?, caretRect: CGRect, fallbackWidth: CGFloat) -> CGFloat {
        guard let characterRect,
              characterRect.width > 0,
              abs(characterRect.minY - caretRect.minY) <= sameLineTolerance
        else { return fallbackWidth }
        return characterRect.width
    }
}

/// カーソルの点滅の状態機械。時計は持たず、次にすることだけを返す。
struct EditorCaretBlink: Equatable {
    enum Phase: Equatable {
        case hidden
        case on
        case off
    }

    enum Event: Equatable {
        case activate
        case deactivate
        case reset
        case tick
    }

    enum Effect: Equatable {
        case none
        case schedule(after: TimeInterval)
        case cancel
    }

    /// 点いている時間と消えている時間(秒)。
    struct Periods: Equatable {
        var on: TimeInterval
        var off: TimeInterval

        /// システムの点滅の時間。保存が無ければ、点いている間も消えている間も 0.5 秒。
        static func system(defaults: SettingsStorage = UserDefaults.standard) -> Periods {
            Periods(
                on: seconds(forKey: "NSTextInsertionPointBlinkPeriodOn", in: defaults),
                off: seconds(forKey: "NSTextInsertionPointBlinkPeriodOff", in: defaults)
            )
        }

        private static func seconds(forKey key: String, in defaults: SettingsStorage) -> TimeInterval {
            guard let milliseconds = (defaults.object(forKey: key) as? NSNumber)?.doubleValue,
                  milliseconds.isFinite,
                  milliseconds > 0
            else { return 0.5 }
            return milliseconds / 1000
        }
    }

    private(set) var phase: Phase = .hidden
    let periods: Periods

    init(periods: Periods) {
        self.periods = periods
    }

    /// 出来事を受けて状態を進め、次にすることを返す。
    mutating func handle(_ event: Event) -> Effect {
        switch (phase, event) {
        case (.hidden, .activate):
            phase = .on
            return .schedule(after: periods.on)
        case (.hidden, _):
            return .none
        case (.on, .tick):
            phase = .off
            return .schedule(after: periods.off)
        case (.off, .tick):
            phase = .on
            return .schedule(after: periods.on)
        case (_, .reset), (_, .activate):
            phase = .on
            return .schedule(after: periods.on)
        case (_, .deactivate):
            phase = .hidden
            return .cancel
        }
    }
}
