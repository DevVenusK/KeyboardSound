import Foundation

/// 키 이벤트의 단계. 누름과 뗌을 구분한다.
enum KeyPhase {
    case down
    case up
}

/// 필터링을 거친 정규화된 키 이벤트.
struct KeyEvent: Equatable {
    let keyCode: Int
    let phase: KeyPhase
}
