import Foundation

/// 합성기에 전달되는 실제 DSP 파라미터.
struct SoundParameters: Equatable {
    var toneFrequency: Double   // Hz, 클릭 중심 주파수
    var sharpness: Double       // 0...1 (어택 가파름 + 노이즈량)
    var decayTime: Double       // 초
    var bodyMix: Double         // 0...1 (바디:노이즈 비율)
    var humanization: Double    // 0...1 (변형 피치 지터 폭)
}
