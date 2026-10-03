import Testing
@testable import TatakiNote

@MainActor
struct PanelStatusItemTests {
    @Test("AC-2, AC-31: 帯の項目は6つで、並びは閉じる・改行・確定+挿入キー・確定+送信キー・文字数・行数")
    func allCasesOrder() {
        #expect(PanelStatusItem.allCases == [.close, .lineBreak, .commit, .commitAndSend, .characterCount, .lineCount])
        #expect(PanelStatusItem.allCases.map(\.displayName) == ["閉じる", "改行", "確定+挿入キー", "確定+送信キー", "文字数", "行数"])
    }

    @Test("AC-31: 帯に出す項目は allCases の順で、非表示にした項目を出さない。すべて非表示なら空")
    func hiddenItemsAreExcluded() {
        let cases: [(Set<PanelStatusItem>, [PanelStatusItem])] = [
            ([], PanelStatusItem.allCases),
            ([.close], [.lineBreak, .commit, .commitAndSend, .characterCount, .lineCount]),
            ([.lineCount, .lineBreak], [.close, .commit, .commitAndSend, .characterCount]),
            ([.commit, .commitAndSend], [.close, .lineBreak, .characterCount, .lineCount]),
            ([.close, .lineBreak, .commit, .commitAndSend, .characterCount], [.lineCount]),
            (Set(PanelStatusItem.allCases), []),
        ]
        for (hidden, expected) in cases {
            let items = PanelStatusItem.visibleItems(
                hidden: hidden,
                commitKey: .commandReturn,
                commitAndSendKey: .commandShiftReturn
            )
            #expect(items == expected, "\(hidden)")
        }
    }

    @Test("AC-17: 確定キーが登録なし(nil)なら確定キーを、確定+送信キーが登録なしなら確定+送信キーを、表示の設定に関わらず出さない")
    func unassignedKeysAreExcluded() {
        let cases: [(PanelShortcut?, PanelShortcut?, Set<PanelStatusItem>, [PanelStatusItem])] = [
            (nil, .commandShiftReturn, [], [.close, .lineBreak, .commitAndSend, .characterCount, .lineCount]),
            (.commandReturn, nil, [], [.close, .lineBreak, .commit, .characterCount, .lineCount]),
            (nil, nil, [], [.close, .lineBreak, .characterCount, .lineCount]),
            (.shiftReturn, .commandReturn, [], PanelStatusItem.allCases),
            (nil, nil, [.close], [.lineBreak, .characterCount, .lineCount]),
            (nil, nil, [.lineBreak, .close, .characterCount, .lineCount], []),
        ]
        for (commitKey, commitAndSendKey, hidden, expected) in cases {
            let items = PanelStatusItem.visibleItems(
                hidden: hidden,
                commitKey: commitKey,
                commitAndSendKey: commitAndSendKey
            )
            #expect(items == expected, "\(String(describing: commitKey)) / \(String(describing: commitAndSendKey)) / \(hidden)")
        }
    }
}
