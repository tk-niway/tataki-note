import CoreGraphics
import Testing
@testable import TatakiNote

struct FindBarFrameTests {
    private static let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test("AC-11: 検索バーの高さは、出ていなければ 0、出ていれば検索の行(と置換の行)の高さ")
    func barHeights() {
        #expect(FindBarMetrics.height(isVisible: false, isReplaceShown: false) == 0)
        #expect(FindBarMetrics.height(isVisible: false, isReplaceShown: true) == 0)
        #expect(FindBarMetrics.height(isVisible: true, isReplaceShown: false) == FindBarMetrics.findRowHeight)
        #expect(
            FindBarMetrics.height(isVisible: true, isReplaceShown: true)
                == FindBarMetrics.findRowHeight + FindBarMetrics.replaceRowHeight
        )
    }

    @Test("AC-11: 検索バーの高さの分だけ窓の枠を下へ伸ばす")
    func stretchesDownward() {
        let change = FindBarFrame.resized(
            CGRect(x: 100, y: 300, width: 500, height: 340), by: 36, upwardShift: 0, visibleFrame: Self.screen
        )
        #expect(change.frame == CGRect(x: 100, y: 264, width: 500, height: 376))
        #expect(change.upwardShift == 0)
        #expect(change.appliedDelta == 36)
    }

    @Test("AC-11: 画面の下端に収まらない分だけ上へずらす")
    func shiftsUpWhenBottomDoesNotFit() {
        let change = FindBarFrame.resized(
            CGRect(x: 100, y: 10, width: 500, height: 340), by: 36, upwardShift: 0, visibleFrame: Self.screen
        )
        #expect(change.frame == CGRect(x: 100, y: 0, width: 500, height: 376))
        #expect(change.upwardShift == 26)
        #expect(change.appliedDelta == 36)
    }

    @Test("AC-11: ずらした分は、縮めると下へ戻って元の枠になる")
    func shrinkRestoresShiftedFrame() {
        let stretched = FindBarFrame.resized(
            CGRect(x: 100, y: 10, width: 500, height: 340), by: 36, upwardShift: 0, visibleFrame: Self.screen
        )
        let restored = FindBarFrame.resized(
            stretched.frame, by: -36, upwardShift: stretched.upwardShift, visibleFrame: Self.screen
        )
        #expect(restored.frame == CGRect(x: 100, y: 10, width: 500, height: 340))
        #expect(restored.upwardShift == 0)
        #expect(restored.appliedDelta == -36)
    }

    @Test("AC-11: 上へずらしても収まらない分は伸ばさない")
    func doesNotStretchBeyondScreen() {
        let frame = CGRect(x: 0, y: 0, width: 500, height: 900)
        let change = FindBarFrame.resized(frame, by: 36, upwardShift: 0, visibleFrame: Self.screen)
        #expect(change.frame == frame)
        #expect(change.upwardShift == 0)
        #expect(change.appliedDelta == 0)
    }

    @Test("AC-11: 上へずらせる余地が一部だけなら、ずらせた分だけ伸ばす")
    func stretchesOnlyWhatFits() {
        let frame = CGRect(x: 0, y: 0, width: 500, height: 890)
        let change = FindBarFrame.resized(frame, by: 36, upwardShift: 0, visibleFrame: Self.screen)
        #expect(change.frame == CGRect(x: 0, y: 0, width: 500, height: 900))
        #expect(change.upwardShift == 10)
        #expect(change.appliedDelta == 10)
    }

    @Test("AC-11: 伸ばせなかった分は、同じ量を縮めると元の枠に戻る")
    func partialStretchRoundTrips() {
        let frame = CGRect(x: 0, y: 0, width: 500, height: 890)
        let stretched = FindBarFrame.resized(frame, by: 36, upwardShift: 0, visibleFrame: Self.screen)
        let restored = FindBarFrame.resized(
            stretched.frame, by: -stretched.appliedDelta, upwardShift: stretched.upwardShift, visibleFrame: Self.screen
        )
        #expect(restored.frame == frame)
        #expect(restored.upwardShift == 0)
    }

    @Test("AC-11: 高さの差が 0 なら枠は変わらない")
    func zeroDeltaKeepsFrame() {
        let frame = CGRect(x: 100, y: 10, width: 500, height: 340)
        let change = FindBarFrame.resized(frame, by: 0, upwardShift: 7, visibleFrame: Self.screen)
        #expect(change.frame == frame)
        #expect(change.upwardShift == 7)
        #expect(change.appliedDelta == 0)
    }

    @Test("AC-11: 検索の行に置換の行を足して伸ばし、同じ順に縮めると元に戻る")
    func stretchAndShrinkInSteps() {
        let original = CGRect(x: 100, y: 300, width: 500, height: 340)
        let firstStretch = FindBarFrame.resized(original, by: 36, upwardShift: 0, visibleFrame: Self.screen)
        let secondStretch = FindBarFrame.resized(
            firstStretch.frame,
            by: FindBarMetrics.replaceRowHeight,
            upwardShift: firstStretch.upwardShift,
            visibleFrame: Self.screen
        )
        #expect(secondStretch.frame == CGRect(x: 100, y: 236, width: 500, height: 404))

        let firstShrink = FindBarFrame.resized(
            secondStretch.frame, by: -FindBarMetrics.replaceRowHeight, upwardShift: secondStretch.upwardShift, visibleFrame: Self.screen
        )
        let secondShrink = FindBarFrame.resized(
            firstShrink.frame, by: -36, upwardShift: firstShrink.upwardShift, visibleFrame: Self.screen
        )
        #expect(secondShrink.frame == original)
        #expect(secondShrink.upwardShift == 0)
    }

    @Test("AC-11: 画面の下端でずらしながら2段に伸ばしても、縮めると元の枠に戻る")
    func shiftedStepsRoundTrip() {
        let original = CGRect(x: 100, y: 10, width: 500, height: 340)
        let first = FindBarFrame.resized(original, by: 36, upwardShift: 0, visibleFrame: Self.screen)
        let second = FindBarFrame.resized(
            first.frame,
            by: FindBarMetrics.replaceRowHeight,
            upwardShift: first.upwardShift,
            visibleFrame: Self.screen
        )
        #expect(second.frame.minY == 0)
        #expect(second.upwardShift == 54)

        let firstShrink = FindBarFrame.resized(
            second.frame, by: -FindBarMetrics.replaceRowHeight, upwardShift: second.upwardShift, visibleFrame: Self.screen
        )
        let secondShrink = FindBarFrame.resized(
            firstShrink.frame, by: -36, upwardShift: firstShrink.upwardShift, visibleFrame: Self.screen
        )
        #expect(secondShrink.frame == original)
        #expect(secondShrink.upwardShift == 0)
    }

    @Test("AC-11: 開くときの大きさは本文の大きさに検索バーの高さを足す")
    func openingSizeAddsBarHeight() {
        let result = FindBarFrame.openingSize(
            bodySize: CGSize(width: 520, height: 340), barHeight: 36, visibleFrame: Self.screen
        )
        #expect(result.size == CGSize(width: 520, height: 376))
        #expect(result.appliedBarHeight == 36)
    }

    @Test("AC-11: 開くときの大きさは画面の高さを越えて伸ばさない")
    func openingSizeStaysWithinScreen() {
        let result = FindBarFrame.openingSize(
            bodySize: CGSize(width: 520, height: 890), barHeight: 36, visibleFrame: Self.screen
        )
        #expect(result.size == CGSize(width: 520, height: 900))
        #expect(result.appliedBarHeight == 10)
    }

    @Test("AC-11: 検索バーが無ければ開くときの大きさは変わらない")
    func openingSizeWithoutBar() {
        let result = FindBarFrame.openingSize(
            bodySize: CGSize(width: 520, height: 340), barHeight: 0, visibleFrame: Self.screen
        )
        #expect(result.size == CGSize(width: 520, height: 340))
        #expect(result.appliedBarHeight == 0)
    }

    @Test("AC-11: 最小の大きさには検索バーの高さを足す")
    func minimumSizeAddsBarHeight() {
        let base = CGSize(width: 320, height: 160)
        #expect(FindBarFrame.minimumSize(base, barHeight: 64) == CGSize(width: 320, height: 224))
        #expect(FindBarFrame.minimumSize(base, barHeight: 0) == base)
    }
}
