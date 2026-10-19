import Carbon.HIToolbox
import Testing
@testable import TatakiNote

@MainActor
struct AppOpenRequestTests {
    private static let presentations: [LaunchPresentation] = [
        .nothing,
        .tutorial,
        .permissionGuide(.firstLaunch),
        .permissionGuide(.launch),
        .permissionGuide(.commitDenied)
    ]

    @Test("AC-6: もう一度開かれたとき、閉じていて確かめ中でも抑止中でもなければ開く。それ以外は開かない")
    func reopenOpensOnlyWhenClosedAndNotConfirmingAndNotSuppressed() {
        for isPresented in [false, true] {
            for isConfirming in [false, true] {
                for isSuppressed in [false, true] {
                    let result = AppOpenRequest.shouldOpenPanelOnReopen(
                        isPanelPresented: isPresented,
                        isConfirmingQuit: isConfirming,
                        isSuppressed: isSuppressed
                    )
                    let expected = !isPresented && !isConfirming && !isSuppressed
                    #expect(result == expected)
                }
            }
        }
    }

    @Test("AC-6: パネルが閉じていれば、もう一度開かれたときに開く")
    func reopenOpensClosedPanel() {
        #expect(AppOpenRequest.shouldOpenPanelOnReopen(isPanelPresented: false, isConfirmingQuit: false, isSuppressed: false))
    }

    @Test("AC-6: パネルが開いているときは何もしない")
    func reopenDoesNothingWhenPanelIsPresented() {
        #expect(!AppOpenRequest.shouldOpenPanelOnReopen(isPanelPresented: true, isConfirmingQuit: false, isSuppressed: false))
    }

    @Test("AC-6: 確かめ中は何もしない")
    func reopenDoesNothingWhileConfirming() {
        #expect(!AppOpenRequest.shouldOpenPanelOnReopen(isPanelPresented: false, isConfirmingQuit: true, isSuppressed: false))
    }

    @Test("AC-6: 抑止中は何もしない")
    func reopenDoesNothingWhenSuppressed() {
        #expect(!AppOpenRequest.shouldOpenPanelOnReopen(isPanelPresented: false, isConfirmingQuit: false, isSuppressed: true))
    }

    @Test("AC-7: 起動の後にパネルを開くのは、何も出さず、ログイン起動でも抑止中でもないときだけ")
    func launchOpensOnlyWhenNothingPresentedAndNotLoginItemAndNotSuppressed() {
        for presentation in Self.presentations {
            for isLoginItem in [false, true] {
                for isSuppressed in [false, true] {
                    let result = AppOpenRequest.shouldOpenPanelOnLaunch(
                        presentation: presentation,
                        isLoginItemLaunch: isLoginItem,
                        isSuppressed: isSuppressed
                    )
                    let expected = presentation == .nothing && !isLoginItem && !isSuppressed
                    #expect(result == expected)
                }
            }
        }
    }

    @Test("AC-7: 何も出さない起動で、ログイン起動でも抑止中でもなければ開く")
    func launchOpensWhenNothingElseHappens() {
        #expect(AppOpenRequest.shouldOpenPanelOnLaunch(presentation: .nothing, isLoginItemLaunch: false, isSuppressed: false))
    }

    @Test("AC-7: チュートリアル・許可の案内が出るときは開かない")
    func launchDoesNotOpenWhenTutorialOrGuideIsShown() {
        for presentation in [LaunchPresentation.tutorial, .permissionGuide(.firstLaunch), .permissionGuide(.launch)] {
            #expect(!AppOpenRequest.shouldOpenPanelOnLaunch(presentation: presentation, isLoginItemLaunch: false, isSuppressed: false))
        }
    }

    @Test("AC-7: ログイン項目としての起動では開かない")
    func launchDoesNotOpenForLoginItem() {
        #expect(!AppOpenRequest.shouldOpenPanelOnLaunch(presentation: .nothing, isLoginItemLaunch: true, isSuppressed: false))
    }

    @Test("AC-7: 抑止中は開かない")
    func launchDoesNotOpenWhenSuppressed() {
        #expect(!AppOpenRequest.shouldOpenPanelOnLaunch(presentation: .nothing, isLoginItemLaunch: false, isSuppressed: true))
    }

    @Test("AC-8: 「アプリを開く」でログイン項目の印があるときだけログイン起動")
    func loginItemLaunchNeedsOpenEventAndLoginItemMark() {
        #expect(AppOpenRequest.isLoginItemLaunch(
            eventID: AEEventID(kAEOpenApplication),
            propData: OSType(keyAELaunchedAsLogInItem)
        ))
    }

    @Test("AC-8: イベントが無ければログイン起動ではない")
    func noEventIsNotLoginItemLaunch() {
        #expect(!AppOpenRequest.isLoginItemLaunch(eventID: nil, propData: nil))
        #expect(!AppOpenRequest.isLoginItemLaunch(eventID: nil, propData: OSType(keyAELaunchedAsLogInItem)))
    }

    @Test("AC-8: もう一度開くイベントはログイン起動ではない")
    func reopenEventIsNotLoginItemLaunch() {
        #expect(!AppOpenRequest.isLoginItemLaunch(
            eventID: AEEventID(kAEReopenApplication),
            propData: OSType(keyAELaunchedAsLogInItem)
        ))
        #expect(!AppOpenRequest.isLoginItemLaunch(eventID: AEEventID(kAEReopenApplication), propData: nil))
    }

    @Test("AC-8: 印が無い・別の印なら、「アプリを開く」でもログイン起動ではない")
    func openEventWithoutLoginItemMarkIsNotLoginItemLaunch() {
        #expect(!AppOpenRequest.isLoginItemLaunch(eventID: AEEventID(kAEOpenApplication), propData: nil))
        #expect(!AppOpenRequest.isLoginItemLaunch(
            eventID: AEEventID(kAEOpenApplication),
            propData: OSType(keyAEPropData)
        ))
    }

    @Test("AC-23: 終了の確かめ中はパネルを開閉しない。確かめ中でなければ開閉してよい")
    func panelToggleIsBlockedOnlyWhileConfirmingQuit() {
        #expect(AppOpenRequest.allowsPanelToggle(isConfirmingQuit: false))
        #expect(!AppOpenRequest.allowsPanelToggle(isConfirmingQuit: true))
    }
}
