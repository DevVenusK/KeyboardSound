import Testing
@testable import KeyboardSound

@Test func spaceIsWide() {
    #expect(KeyGroupMap.group(for: 49) == .wide)   // space
}

@Test func returnAndDeleteAndTabAreWide() {
    #expect(KeyGroupMap.group(for: 36) == .wide)    // return
    #expect(KeyGroupMap.group(for: 51) == .wide)    // delete (backspace)
    #expect(KeyGroupMap.group(for: 48) == .wide)    // tab
}

@Test func arrowsAreWide() {
    for code in [123, 124, 125, 126] {              // left, right, down, up
        #expect(KeyGroupMap.group(for: code) == .wide)
    }
}

@Test func modifiersAreWide() {
    for code in [54, 55, 56, 60, 58, 61, 59, 62, 57, 63] {
        #expect(KeyGroupMap.group(for: code) == .wide)
    }
}

@Test func letterIsNormal() {
    #expect(KeyGroupMap.group(for: 0) == .normal)   // 'a'
    #expect(KeyGroupMap.group(for: 1) == .normal)   // 's'
}
