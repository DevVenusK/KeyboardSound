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
