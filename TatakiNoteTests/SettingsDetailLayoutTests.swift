import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct SettingsDetailLayoutTests {
    @Test("AC-5: 右の余白は今(20pt)より広く、左・上・下は今のまま")
    func trailingIsWiderThanBefore() {
        #expect(SettingsDetailLayout.leading == 20)
        #expect(SettingsDetailLayout.top == 16)
        #expect(SettingsDetailLayout.bottom == 20)
        #expect(SettingsDetailLayout.trailing > 20)
    }
}
