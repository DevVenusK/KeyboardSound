import Foundation

/// 합성기에 전달되는 실제 DSP 파라미터.
struct SoundParameters: Equatable {
    var toneFrequency: Double   // Hz, 클릭 중심 주파수
    var sharpness: Double       // 0...1 (어택 가파름 + 노이즈량)
    var decayTime: Double       // 초
    var bodyMix: Double         // 0...1 (바디:노이즈 비율)
    var humanization: Double    // 0...1 (변형 피치 지터 폭)
    var clickAmount: Double = 0 // 0...1 (청축 딸깍 트랜지언트 세기)
    var weight: Double = 0.5    // 0...1 (저역 무게: 서브/기본 모드 강조, 0.5=중립)
}
