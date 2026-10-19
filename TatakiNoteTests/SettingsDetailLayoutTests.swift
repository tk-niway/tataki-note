import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct SettingsDetailLayoutTests {
    @Test("AC-4: 右の内容の余白は左右 28・上 8・下 28、見出しの余白は上 18・左右 28・下 6")
    func detailPaddingValues() {
        #expect(SettingsDetailLayout.leading == 28)
        #expect(SettingsDetailLayout.trailing == 28)
        #expect(SettingsDetailLayout.top == 8)
        #expect(SettingsDetailLayout.bottom == 28)
        #expect(SettingsDetailLayout.headerTop == 18)
        #expect(SettingsDetailLayout.headerBottom == 6)
    }
}
