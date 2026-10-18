import Carbon.HIToolbox
import Foundation

/// アイコンから開かれたとき・ホットキーのときに、パネルを開くかの判定。
enum AppOpenRequest {
    /// 起動の後にパネルを開くか。起動時に何も出さず、ログイン項目としての起動でも抑止中でもないときだけ true。
    static func shouldOpenPanelOnLaunch(presentation: LaunchPresentation, isLoginItemLaunch: Bool, isSuppressed: Bool) -> Bool {
        presentation == .nothing && !isLoginItemLaunch && !isSuppressed
    }

    /// もう一度開かれたときにパネルを開くか。パネルが閉じていて、終了の確かめ中でも抑止中でもないときだけ true。
    static func shouldOpenPanelOnReopen(isPanelPresented: Bool, isConfirmingQuit: Bool, isSuppressed: Bool) -> Bool {
        !isPanelPresented && !isConfirmingQuit && !isSuppressed
    }

    /// ホットキー・入力欄を選んだことでの自動表示でパネルを開閉してよいか。終了の確かめ中は false。
    static func allowsPanelToggle(isConfirmingQuit: Bool) -> Bool {
        !isConfirmingQuit
    }

    /// 起動の Apple Event の値から、ログイン項目として起動されたかを返す。
    static func isLoginItemLaunch(eventID: AEEventID?, propData: OSType?) -> Bool {
        eventID == AEEventID(kAEOpenApplication) && propData == OSType(keyAELaunchedAsLogInItem)
    }
}
