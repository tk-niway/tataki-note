import CoreGraphics
import Observation
import os
import Testing
@testable import TatakiNote

@MainActor
struct PanelSizingTests {
    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
    private let defaultSize = CGSize(width: 520, height: 340)

    private func openedSizing(defaultSize: CGSize = CGSize(width: 520, height: 340)) -> PanelSizing {
        let sizing = PanelSizing()
        sizing.beginOpening(defaultSize: defaultSize)
        return sizing
    }

    private func countHeldSizeChanges(of sizing: PanelSizing) -> OSAllocatedUnfairLock<Int> {
        let changes = OSAllocatedUnfairLock(initialState: 0)
        withObservationTracking {
            _ = sizing.heldSize
        } onChange: {
            changes.withLock { $0 += 1 }
        }
        return changes
    }

    // MARK: - 開くときの大きさ

    @Test("AC-2: 開くときの大きさは既定の大きさのままで、可視領域より大きければ収まるまで縮む")
    func openingSizeUsesBaseSizeClampedToVisibleFrame() {
        let sizing = openedSizing()
        #expect(sizing.openingSize(in: visible) == defaultSize)

        let huge = openedSizing(defaultSize: CGSize(width: 2000, height: 1000))
        #expect(huge.openingSize(in: visible) == CGSize(width: 1440, height: 875))

        let wide = openedSizing(defaultSize: CGSize(width: 2000, height: 400))
        #expect(wide.openingSize(in: visible) == CGSize(width: 1440, height: 400))
    }

    @Test("AC-4: ドラッグで決めた大きさを保っている間は、開くときの大きさもその大きさになり、挿入すると既定の大きさに戻る")
    func openingSizeFollowsHeldSizeUntilInserted() {
        let sizing = openedSizing()
        sizing.userDidResize(from: defaultSize, to: CGSize(width: 700, height: 600))
        #expect(sizing.openingSize(in: visible) == CGSize(width: 700, height: 600))

        sizing.handleCommitOutcome(.inserted)
        #expect(sizing.openingSize(in: visible) == defaultSize)
    }

    // MARK: - ドラッグで決めた大きさ

    @Test("AC-4, AC-15, AC-18: ドラッグで変わった辺だけを保つ(幅だけなら高さの下限は変えず、高さだけなら幅は変えない)。大きさの変わらないドラッグでは保っている大きさを変えない")
    func userDidResizeKeepsOnlyChangedEdges() {
        let sizing = openedSizing()

        sizing.userDidResize(from: CGSize(width: 520, height: 500), to: CGSize(width: 700, height: 500))
        #expect(sizing.heldSize == CGSize(width: 700, height: 340))
        #expect(sizing.baseSize == CGSize(width: 700, height: 340))

        sizing.userDidResize(from: CGSize(width: 700, height: 500), to: CGSize(width: 700, height: 600))
        #expect(sizing.heldSize == CGSize(width: 700, height: 600))
        #expect(sizing.baseSize == CGSize(width: 700, height: 600))

        let changes = countHeldSizeChanges(of: sizing)
        sizing.userDidResize(from: CGSize(width: 700, height: 600), to: CGSize(width: 700, height: 600))
        #expect(sizing.heldSize == CGSize(width: 700, height: 600))
        #expect(changes.withLock { $0 } == 0)
    }

    @Test("AC-18: 保っていない状態で大きさの変わらないドラッグをしても何も覚えず、観測している側にも知らせない")
    func userDidResizeWithoutChangeKeepsNothing() {
        let sizing = openedSizing()
        let changes = countHeldSizeChanges(of: sizing)

        sizing.userDidResize(from: CGSize(width: 520, height: 500), to: CGSize(width: 520, height: 500))

        #expect(sizing.heldSize == nil)
        #expect(sizing.baseSize == defaultSize)
        #expect(changes.withLock { $0 } == 0)
    }

    @Test("AC-15: 画面に収まるよう縮めて開いた幅は、高さだけのドラッグで保つ幅にならない")
    func heightOnlyDragKeepsDefaultWidth() {
        let sizing = openedSizing()

        sizing.userDidResize(from: CGSize(width: 400, height: 340), to: CGSize(width: 400, height: 450))

        #expect(sizing.heldSize == CGSize(width: 520, height: 450))
    }

    @Test("AC-18: ドラッグで最小の大きさを下回る値が来ても、保つ大きさは 320×160 まで")
    func userDidResizeClampsToMinimum() {
        let sizing = openedSizing()

        sizing.userDidResize(from: defaultSize, to: CGSize(width: 300, height: 100))

        #expect(PanelSizing.minimumSize == CGSize(width: 320, height: 160))
        #expect(sizing.heldSize == CGSize(width: 320, height: 160))
    }

    @Test("AC-17, AC-18: ドラッグで変わらなかった辺は、開いたときの設定の既定の値")
    func unchangedEdgeUsesOpenedDefaultSize() {
        let sizing = openedSizing(defaultSize: CGSize(width: 600, height: 400))

        sizing.userDidResize(from: CGSize(width: 600, height: 400), to: CGSize(width: 700, height: 400))

        #expect(sizing.heldSize == CGSize(width: 700, height: 400))
    }

    // MARK: - 確定の結果

    @Test("AC-6, AC-7, AC-18: 挿入できなかったときは保っている大きさを保ち、挿入できたら捨てて次は設定の既定の大きさ")
    func commitOutcomeResetsOnlyWhenInserted() {
        let sizing = openedSizing()
        sizing.userDidResize(from: defaultSize, to: CGSize(width: 700, height: 600))

        sizing.handleCommitOutcome(.notInserted)
        #expect(sizing.heldSize == CGSize(width: 700, height: 600))
        #expect(sizing.baseSize == CGSize(width: 700, height: 600))

        let changes = countHeldSizeChanges(of: sizing)
        sizing.handleCommitOutcome(.inserted)
        #expect(sizing.heldSize == nil)
        #expect(sizing.baseSize == defaultSize)
        #expect(changes.withLock { $0 } == 1)
    }

    @Test("AC-18: 保っていない状態で挿入できても、保っている大きさは nil のままで、観測している側に知らせない")
    func commitOutcomeWithoutHeldSizeDoesNotNotify() {
        let sizing = openedSizing()
        let changes = countHeldSizeChanges(of: sizing)

        sizing.handleCommitOutcome(.inserted)

        #expect(sizing.heldSize == nil)
        #expect(changes.withLock { $0 } == 0)
    }

    // MARK: - 設定の既定の大きさ

    @Test("AC-16, AC-18: 作った直後は保っている大きさが無く、開くと設定の既定の大きさが開く大きさ・縮む下限になる")
    func beginOpeningUsesDefaultSize() {
        let sizing = PanelSizing()
        #expect(sizing.heldSize == nil)

        sizing.beginOpening(defaultSize: CGSize(width: 600, height: 400))

        #expect(sizing.baseSize == CGSize(width: 600, height: 400))
        #expect(sizing.heldSize == nil)
    }

    @Test("AC-17, AC-18: 保っていなければ(大きさの変わらないドラッグだけも含む)、設定を変えて開き直すと新しい既定の大きさ")
    func newDefaultSizeAppliesWhenNothingIsHeld() {
        let sizing = PanelSizing()
        sizing.beginOpening(defaultSize: CGSize(width: 600, height: 400))
        sizing.beginOpening(defaultSize: CGSize(width: 800, height: 500))
        #expect(sizing.baseSize == CGSize(width: 800, height: 500))

        let draggedWithoutChange = PanelSizing()
        draggedWithoutChange.beginOpening(defaultSize: CGSize(width: 600, height: 400))
        draggedWithoutChange.userDidResize(from: CGSize(width: 600, height: 400), to: CGSize(width: 600, height: 400))
        draggedWithoutChange.beginOpening(defaultSize: CGSize(width: 800, height: 500))
        #expect(draggedWithoutChange.baseSize == CGSize(width: 800, height: 500))
        #expect(draggedWithoutChange.heldSize == nil)
    }

    @Test("AC-7, AC-17, AC-18: 保っている間は設定を変えても挿入するまでその大きさで開き、挿入の後は変えた後の既定の大きさ")
    func heldSizeWinsUntilInserted() {
        let sizing = PanelSizing()
        sizing.beginOpening(defaultSize: CGSize(width: 600, height: 400))
        sizing.userDidResize(from: CGSize(width: 600, height: 400), to: CGSize(width: 700, height: 450))

        let changes = countHeldSizeChanges(of: sizing)
        sizing.beginOpening(defaultSize: CGSize(width: 800, height: 500))
        #expect(sizing.baseSize == CGSize(width: 700, height: 450))
        #expect(sizing.heldSize == CGSize(width: 700, height: 450))
        #expect(changes.withLock { $0 } == 0)

        sizing.handleCommitOutcome(.inserted)
        #expect(sizing.heldSize == nil)
        sizing.beginOpening(defaultSize: CGSize(width: 800, height: 500))
        #expect(sizing.baseSize == CGSize(width: 800, height: 500))
    }

    @Test("AC-17: 開いている間は、次に開く(beginOpening)まで開いたときの既定の大きさを使い続ける")
    func openedDefaultSizeStaysWhileOpen() {
        let sizing = PanelSizing()
        sizing.beginOpening(defaultSize: CGSize(width: 600, height: 400))

        sizing.handleCommitOutcome(.notInserted)
        #expect(sizing.openedDefaultSize == CGSize(width: 600, height: 400))
        #expect(sizing.baseSize == CGSize(width: 600, height: 400))
    }

    @Test("AC-18: 保っている大きさがドラッグで変わると、観測している側に知らせる")
    func userDidResizeNotifiesObservers() {
        let sizing = openedSizing()
        let changes = countHeldSizeChanges(of: sizing)

        sizing.userDidResize(from: defaultSize, to: CGSize(width: 700, height: 340))

        #expect(sizing.heldSize == CGSize(width: 700, height: 340))
        #expect(changes.withLock { $0 } == 1)
    }
}
