import Foundation

/// 사운드 그룹. normal = 일반 클릭, wide = 낮고 묵직한 thock.
enum KeyGroup {
    case normal
    case wide
}

/// macOS 가상 키코드 → 사운드 그룹 매핑.
enum KeyGroupMap {
    /// thock(wide) 그룹으로 처리할 키코드 집합.
    static let wideKeyCodes: Set<Int> = [
        49,                 // space
        36, 76,             // return, keypad enter
        51, 117,            // delete(backspace), forward delete
        48,                 // tab
        53,                 // escape
        123, 124, 125, 126, // arrows: left, right, down, up
        54, 55,             // command (right, left)
        56, 60,             // shift (left, right)
        58, 61,             // option (left, right)
        59, 62,             // control (left, right)
        57,                 // caps lock
        63,                 // fn
    ]

    static func group(for keyCode: Int) -> KeyGroup {
        wideKeyCodes.contains(keyCode) ? .wide : .normal
    }
}
