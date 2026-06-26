import Foundation

/// 스위치 느낌 프리셋. tone/sharpness는 슬라이더 기본값(0...1),
/// decayTime/bodyMix/humanization은 비노출 내부값.
struct Preset: Equatable, Identifiable {
    let id: String
    let name: String
    let tone: Double
    let sharpness: Double
    let decayTime: Double
    let bodyMix: Double
    let humanization: Double
    let clickAmount: Double

    static let blue  = Preset(id: "blue",  name: "청축",  tone: 0.80, sharpness: 0.85, decayTime: 0.045, bodyMix: 0.25, humanization: 0.15, clickAmount: 0.80)
    static let brown = Preset(id: "brown", name: "갈축",  tone: 0.55, sharpness: 0.55, decayTime: 0.060, bodyMix: 0.45, humanization: 0.20, clickAmount: 0.00)
    static let red   = Preset(id: "red",   name: "적축",  tone: 0.45, sharpness: 0.35, decayTime: 0.050, bodyMix: 0.50, humanization: 0.15, clickAmount: 0.00)
    static let topre = Preset(id: "topre", name: "토프레", tone: 0.22, sharpness: 0.30, decayTime: 0.095, bodyMix: 0.72, humanization: 0.25, clickAmount: 0.00)

    static let all: [Preset] = [.blue, .brown, .red, .topre]

    static func with(id: String) -> Preset? {
        all.first { $0.id == id }
    }
}

/// tone/sharpness 슬라이더(0...1) → 합성 파라미터 변환.
enum SoundParameterMapping {
    /// tone 슬라이더(0...1)를 로그 스케일 주파수로. wide 그룹은 한 옥타브 낮춤.
    static func toneFrequency(tone: Double, group: KeyGroup) -> Double {
        let minHz = 600.0
        let maxHz = 4000.0
        let base = minHz * pow(maxHz / minHz, max(0, min(1, tone)))
        return group == .wide ? base * 0.5 : base
    }
}
