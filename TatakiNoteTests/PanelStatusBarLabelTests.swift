import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct PanelStatusBarLabelTests {
    private func label(of item: PanelStatusItem) -> String? {
        let content = PanelStatusBarContent(
            text: "",
            items: [item],
            commitKeyText: nil,
            commitAndSendKeyText: nil
        )
        guard case .keyHint(_, _, let label)? = content.entries.first else { return nil }
        return label
    }

    @Test("AC-16: 帯の「改行」「閉じる」の文言は、設定の「帯に出す項目」の名前と同じ")
    func lineBreakAndCloseLabelsMatchDisplayNames() {
        #expect(label(of: .lineBreak) == PanelStatusItem.lineBreak.displayName)
        #expect(label(of: .close) == PanelStatusItem.close.displayName)
    }

    @Test("AC-16: 帯の「改行」「閉じる」の文言は今と同じ文になる")
    func lineBreakAndCloseLabelsAreUnchanged() {
        #expect(label(of: .lineBreak) == "改行")
        #expect(label(of: .close) == "閉じる")
    }
}
