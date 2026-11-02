import ApplicationServices
import Testing
@testable import TatakiNote

struct FocusedElementProbeIdentityTests {
    private let element = AXUIElementCreateApplication(4001)
    private let otherElement = AXUIElementCreateApplication(4002)

    @Test("AC-5: 同じインスタンスの要素は同じ要素")
    func sameInstanceIsSame() {
        #expect(FocusedElementProbe.isSameElement(element, element))
    }

    @Test("AC-5: 別の pid の要素は別の要素")
    func differentProcessIsDifferent() {
        #expect(!FocusedElementProbe.isSameElement(element, otherElement))
        #expect(!FocusedElementProbe.isSameElement(otherElement, element))
    }

    @Test("AC-5: 片方が nil なら別の要素")
    func nilIsNeverSame() {
        #expect(!FocusedElementProbe.isSameElement(nil, element))
        #expect(!FocusedElementProbe.isSameElement(element, nil))
    }

    @Test("AC-5: 両方 nil でも同じ要素とは言わない")
    func bothNilIsNotSame() {
        #expect(!FocusedElementProbe.isSameElement(nil, nil))
    }
}
