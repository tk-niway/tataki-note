import Foundation
import Observation

/// 設定画面の「修飾キーで移動・サイズ変更」の状態。
@Observable final class PanelPointerSettingsModel {
    @ObservationIgnored private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// 同じ組み合わせを拒んだ操作。拒んだ行に理由を出す。受け付けた操作をすると nil に戻る。
    private(set) var rejectedAction: PanelPointerAction?

    /// 拒んだ回数。拒むたびに1増やす。
    private(set) var rejectionCount = 0

    /// チェックが入っているか。
    func isOn(_ modifier: PanelPointerModifier, for action: PanelPointerAction) -> Bool {
        settings.pointerModifiers(for: action).contains(modifier)
    }

    /// チェックを入れる・外す。もう一方と同じ組み合わせになるなら変えずに rejectedAction を入れる。
    func setModifier(_ modifier: PanelPointerModifier, isOn: Bool, for action: PanelPointerAction) {
        var modifiers = settings.pointerModifiers(for: action)
        if isOn {
            modifiers.insert(modifier)
        } else {
            modifiers.remove(modifier)
        }
        if settings.selectPointerModifiers(modifiers, for: action) {
            rejectedAction = nil
        } else {
            rejectedAction = action
            rejectionCount += 1
        }
    }

    /// その操作が使えないか(チェックが1つも無い)。
    func isDisabled(_ action: PanelPointerAction) -> Bool {
        settings.pointerModifiers(for: action).isEmpty
    }

    /// 拒んだ理由。rejectedAction がその操作のときだけ返す。
    func rejectionMessage(for action: PanelPointerAction) -> String? {
        rejectedAction == action ? Self.rejectionText(for: action) : nil
    }

    /// 行の名前。
    static func title(for action: PanelPointerAction) -> String {
        switch action {
        case .move: String(localized: "ウィンドウの移動")
        case .resize: String(localized: "ウィンドウのサイズ変更")
        }
    }

    /// 拒んだ理由の文。
    static func rejectionText(for action: PanelPointerAction) -> String {
        switch action {
        case .move: String(localized: "サイズ変更と同じ組み合わせは選べません")
        case .resize: String(localized: "移動と同じ組み合わせは選べません")
        }
    }

    /// チェックが無いときの注記。
    static var disabledText: String {
        String(localized: "チェックが無いあいだは使えません")
    }

    /// グループの説明。
    static var groupFooter: String {
        String(localized: "修飾キーを押したままカーソルを動かすと、パネルが動く・大きさが変わる")
    }
}
