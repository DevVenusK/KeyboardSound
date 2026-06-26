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

    static let clicky  = Preset(id: "clicky",  name: "Clicky",  tone: 0.78, sharpness: 0.85, decayTime: 0.045, bodyMix: 0.25, humanization: 0.15, clickAmount: 0.80)
    static let tactile = Preset(id: "tactile", name: "Tactile", tone: 0.55, sharpness: 0.60, decayTime: 0.060, bodyMix: 0.45, humanization: 0.20, clickAmount: 0.00)
    static let linear  = Preset(id: "linear",  name: "Linear",  tone: 0.50, sharpness: 0.35, decayTime: 0.050, bodyMix: 0.55, humanization: 0.15, clickAmount: 0.00)
    static let thock   = Preset(id: "thock",   name: "Thock",   tone: 0.25, sharpness: 0.30, decayTime: 0.090, bodyMix: 0.70, humanization: 0.25, clickAmount: 0.00)

    static let all: [Preset] = [.clicky, .tactile, .linear, .thock]

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
