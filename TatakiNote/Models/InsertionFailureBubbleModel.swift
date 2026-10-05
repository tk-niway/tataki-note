import Foundation
import Observation

/// 挿入できなかったことを知らせる吹き出しの状態と、メニューバーのアイコンを出すかの決まり。
@Observable
final class InsertionFailureBubbleModel {
    static let message = String(localized: "挿入できませんでした")
    static let displayDuration: Duration = .seconds(5)

    private(set) var isPresented = false
    private(set) var presentationID = 0

    var forcesMenuBarIcon: Bool { isPresented }

    /// 吹き出しを出す状態にして、この表示の番号を返す。
    @discardableResult
    func present() -> Int {
        presentationID += 1
        isPresented = true
        return presentationID
    }

    /// 吹き出しを出していない状態にする。
    func dismiss() {
        isPresented = false
    }

    /// 設定と吹き出しの状態から、メニューバーのアイコンを出すか。
    func isMenuBarIconInserted(isIconShownSetting: Bool) -> Bool {
        isIconShownSetting || forcesMenuBarIcon
    }

    /// アイコンの出し入れが書き戻されたときに設定へ反映する。吹き出しを閉じるべきなら `true`。
    func menuBarIconInsertionDidChange(to isInserted: Bool, settings: AppSettings) -> Bool {
        if isInserted {
            if !forcesMenuBarIcon {
                settings.isMenuBarIconShown = true
            }
            return false
        }
        settings.isMenuBarIconShown = false
        return isPresented
    }
}
