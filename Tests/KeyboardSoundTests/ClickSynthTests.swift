import Testing
import Foundation
@testable import KeyboardSound

private let params = SoundParameters(toneFrequency: 2000, sharpness: 0.7,
                                     decayTime: 0.05, bodyMix: 0.4, humanization: 0.2)

@Test func renderIsNotSilent() {
    let synth = ClickSynth(sampleRate: 44100)
    let s = synth.render(parameters: params, phase: .down, pitchMultiplier: 1.0, seed: 1)
    let rms = sqrt(s.reduce(0) { $0 + Double($1 * $1) } / Double(s.count))
    #expect(rms > 0.001)
}

@Test func renderLengthMatchesDecay() {
    let synth = ClickSynth(sampleRate: 44100)
    let s = synth.render(parameters: params, phase: .down, pitchMultiplier: 1.0, seed: 1)
    // 0.05s * 44100 ≈ 2205 samples
    #expect(s.count >= 2000 && s.count <= 2400)
}

@Test func sameSeedSameOutput() {
    let synth = ClickSynth(sampleRate: 44100)
    let a = synth.render(parameters: params, phase: .down, pitchMultiplier: 1.0, seed: 99)
    let b = synth.render(parameters: params, phase: .down, pitchMultiplier: 1.0, seed: 99)
    #expect(a == b)
}

@Test func upIsShorterThanDown() {
    let synth = ClickSynth(sampleRate: 44100)
    let down = synth.render(parameters: params, phase: .down, pitchMultiplier: 1.0, seed: 1)
    let up = synth.render(parameters: params, phase: .up, pitchMultiplier: 1.0, seed: 1)
    #expect(up.count < down.count)
}

@Test func outputIsBounded() {
    let synth = ClickSynth(sampleRate: 44100)
    let s = synth.render(parameters: params, phase: .down, pitchMultiplier: 1.0, seed: 5)
    for v in s {
        #expect(v.isFinite)
        #expect(v >= -1.0 && v <= 1.0)
    }
}

@Test func clickAmountChangesOutput() {
    let synth = ClickSynth(sampleRate: 44100)
    let base = SoundParameters(toneFrequency: 2000, sharpness: 0.7, decayTime: 0.05,
                               bodyMix: 0.4, humanization: 0.2, clickAmount: 0.0)
    let clicky = SoundParameters(toneFrequency: 2000, sharpness: 0.7, decayTime: 0.05,
                                 bodyMix: 0.4, humanization: 0.2, clickAmount: 0.9)
    let a = synth.render(parameters: base, phase: .down, pitchMultiplier: 1.0, seed: 7)
    let b = synth.render(parameters: clicky, phase: .down, pitchMultiplier: 1.0, seed: 7)
    #expect(a != b)
}

@Test func clickAddsHighFrequencyContent() {
    // 합성기가 피크 정규화를 하므로 "절대 에너지 증가"는 불변량이 아니다.
    // 대신 클릭 자켓(~5kHz 버스트)이 고주파 함량을 높인다는 정규화-불변 속성을 검증한다.
    // HF 비율 = Σ(1차 차분²)/Σ(샘플²) — 분자·분모가 같은 정규화 계수로 스케일되어 불변.
    let synth = ClickSynth(sampleRate: 44100)
    let base = SoundParameters(toneFrequency: 2000, sharpness: 0.7, decayTime: 0.05,
                               bodyMix: 0.4, humanization: 0.2, clickAmount: 0.0)
    let clicky = SoundParameters(toneFrequency: 2000, sharpness: 0.7, decayTime: 0.05,
                                 bodyMix: 0.4, humanization: 0.2, clickAmount: 0.9)
    let a = synth.render(parameters: base, phase: .down, pitchMultiplier: 1.0, seed: 7)
    let b = synth.render(parameters: clicky, phase: .down, pitchMultiplier: 1.0, seed: 7)
    let window = min(220, a.count, b.count)   // 첫 ~5ms
    func hfRatio(_ s: [Float]) -> Double {
        var diff = 0.0, energy = 0.0
        for i in 1..<window {
            let d = Double(s[i] - s[i - 1]); diff += d * d
            energy += Double(s[i] * s[i])
        }
        return energy > 0 ? diff / energy : 0
    }
    #expect(hfRatio(b) > hfRatio(a))
}

@Test func outputBoundedWithMaxClick() {
    let synth = ClickSynth(sampleRate: 44100)
    let p = SoundParameters(toneFrequency: 2000, sharpness: 0.7, decayTime: 0.05,
                            bodyMix: 0.4, humanization: 0.2, clickAmount: 1.0)
    let s = synth.render(parameters: p, phase: .down, pitchMultiplier: 1.0, seed: 3)
    for v in s { #expect(v.isFinite && v >= -1.0 && v <= 1.0) }
}
