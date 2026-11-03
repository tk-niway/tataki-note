import Testing
@testable import TatakiNote

struct FindBarMotionTests {
    @Test("AC-46: 動きを止めているときは検索バーの出入りの動きが無く、使っているときは動きがある")
    func animationFollowsReducedFlag() {
        #expect(FindBarMotion.animation(isReduced: true) == nil)
        #expect(FindBarMotion.animation(isReduced: false) != nil)
    }
}
