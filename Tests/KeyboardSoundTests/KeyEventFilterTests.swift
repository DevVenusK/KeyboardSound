import Testing
@testable import KeyboardSound

@Test func keyDownEmitsDown() {
    let e = KeyEventFilter.decide(type: .keyDown, keyCode: 0, isAutorepeat: false,
                                  previousFlags: 0, currentFlags: 0, modifierMask: 0)
    #expect(e == KeyEvent(keyCode: 0, phase: .down))
}

@Test func autorepeatIsIgnored() {
    let e = KeyEventFilter.decide(type: .keyDown, keyCode: 0, isAutorepeat: true,
                                  previousFlags: 0, currentFlags: 0, modifierMask: 0)
    #expect(e == nil)
}

@Test func keyUpEmitsUp() {
    let e = KeyEventFilter.decide(type: .keyUp, keyCode: 0, isAutorepeat: false,
                                  previousFlags: 0, currentFlags: 0, modifierMask: 0)
    #expect(e == KeyEvent(keyCode: 0, phase: .up))
}

@Test func modifierPressEmitsDown() {
    let mask: UInt64 = 0b1000
    let e = KeyEventFilter.decide(type: .flagsChanged, keyCode: 56, isAutorepeat: false,
                                  previousFlags: 0, currentFlags: mask, modifierMask: mask)
    #expect(e == KeyEvent(keyCode: 56, phase: .down))
}

@Test func modifierReleaseEmitsUp() {
    let mask: UInt64 = 0b1000
    let e = KeyEventFilter.decide(type: .flagsChanged, keyCode: 56, isAutorepeat: false,
                                  previousFlags: mask, currentFlags: 0, modifierMask: mask)
    #expect(e == KeyEvent(keyCode: 56, phase: .up))
}

@Test func modifierUnchangedEmitsNil() {
    let mask: UInt64 = 0b1000
    let e = KeyEventFilter.decide(type: .flagsChanged, keyCode: 56, isAutorepeat: false,
                                  previousFlags: mask, currentFlags: mask, modifierMask: mask)
    #expect(e == nil)
}

@Test func modifierMaskMappingKnownKeys() {
    #expect(KeyEventFilter.modifierMask(forKeyCode: 56) != nil)   // shift
    #expect(KeyEventFilter.modifierMask(forKeyCode: 0) == nil)    // 'a' 아님
}
