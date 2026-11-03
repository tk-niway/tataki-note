import Testing
@testable import TatakiNote

struct KeyCodeTests {
    @Test("AC-3: キーコードの名前と値は、esc 53・↩ 36・テンキーの Enter 76・Tab 48・↑ 126・↓ 125・delete 51・forward delete 117")
    func keyCodeValues() {
        #expect(KeyCode.escape == 53)
        #expect(KeyCode.returnKey == 36)
        #expect(KeyCode.keypadEnter == 76)
        #expect(KeyCode.tab == 48)
        #expect(KeyCode.upArrow == 126)
        #expect(KeyCode.downArrow == 125)
        #expect(KeyCode.delete == 51)
        #expect(KeyCode.forwardDelete == 117)
    }
}
