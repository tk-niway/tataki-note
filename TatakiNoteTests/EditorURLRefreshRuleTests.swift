import Foundation
import Testing
@testable import TatakiNote

struct EditorURLRefreshRuleTests {
    private func refreshes(
        isStillSelecting: Bool = false,
        isApplyingURLFolds: Bool = false,
        isChangingText: Bool = false,
        hasPendingEdits: Bool = false,
        isSelectionChanged: Bool = false
    ) -> Bool {
        EditorURLRefreshRule.refreshesOnSelectionChange(
            isStillSelecting: isStillSelecting,
            isApplyingURLFolds: isApplyingURLFolds,
            isChangingText: isChangingText,
            hasPendingEdits: hasPendingEdits,
            isSelectionChanged: isSelectionChanged
        )
    }

    @Test("AC-4: カーソルの移動だけのときは見え方を決め直す")
    func refreshesWhenOnlyTheCaretMoved() {
        #expect(refreshes(isSelectionChanged: true))
    }

    @Test("AC-4: 文章も選択も前回の決め直しから変わっていなければ決め直さない")
    func doesNotRefreshWhenNothingChanged() {
        #expect(!refreshes())
    }

    @Test("AC-4: 文字の変更の途中(didChangeText の前)の選択の変化では決め直さない")
    func doesNotRefreshInTheMiddleOfATextChange() {
        for isSelectionChanged in [true, false] {
            #expect(!refreshes(isChangingText: true, hasPendingEdits: true, isSelectionChanged: isSelectionChanged))
        }
    }

    @Test("AC-4: 変更が許されただけで文字が変わっていないときは、選択が変わっていれば決め直す")
    func refreshesWhenTextChangeWasAllowedButNothingChanged() {
        #expect(refreshes(isChangingText: true, hasPendingEdits: false, isSelectionChanged: true))
        #expect(!refreshes(isChangingText: true, hasPendingEdits: false, isSelectionChanged: false))
    }

    @Test("AC-4: 記録した変更が残っているときは、選択が同じでも決め直す")
    func refreshesWhenEditsArePending() {
        for isSelectionChanged in [true, false] {
            #expect(refreshes(hasPendingEdits: true, isSelectionChanged: isSelectionChanged))
        }
    }

    @Test("AC-4: 選択の途中・付け直しの中は、何が変わっていても決め直さない")
    func doesNotRefreshWhileSelectingOrApplying() {
        for hasPendingEdits in [true, false] {
            for isSelectionChanged in [true, false] {
                #expect(!refreshes(isStillSelecting: true, hasPendingEdits: hasPendingEdits, isSelectionChanged: isSelectionChanged))
                #expect(!refreshes(isApplyingURLFolds: true, hasPendingEdits: hasPendingEdits, isSelectionChanged: isSelectionChanged))
            }
        }
    }
}
