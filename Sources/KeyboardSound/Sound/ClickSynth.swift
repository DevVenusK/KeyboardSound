import Foundation

/// 파라미터로부터 기계식 클릭음 PCM 샘플([Float])을 절차적으로 합성한다. 순수 함수.
struct ClickSynth {
    let sampleRate: Double

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    func render(parameters: SoundParameters, phase: KeyPhase, pitchMultiplier: Double, seed: UInt64) -> [Float] {
        var rng = SplitMix64(seed: seed)
        let isUp = (phase == .up)

        // 릴리스(up) 클릭은 더 짧고 약하게.
        let decay = parameters.decayTime * (isUp ? 0.6 : 1.0)
        let amplitude: Float = isUp ? 0.5 : 1.0

        let count = max(1, Int(decay * sampleRate))
        var out = [Float](repeating: 0, count: count)

        let toneHz = parameters.toneFrequency * pitchMultiplier
        let bodyHz = toneHz * 0.5
        let q = 1.0 + parameters.sharpness * 6.0
        var bandpass = BiquadBandpass(sampleRate: sampleRate, centerHz: toneHz, q: q)

        let noiseMix = Float(1.0 - parameters.bodyMix)
        let bodyMix = Float(parameters.bodyMix)
        let attackSamples = max(1, Int(0.001 * sampleRate))   // 1ms 어택
        let decayConst = max(0.0001, decay / 5.0)             // 5 시정수
        let twoPiBodyOverSr = 2.0 * Double.pi * bodyHz / sampleRate

        for n in 0..<count {
            // 엔벨로프: 선형 어택 후 지수 감쇠
            let env: Float
            if n < attackSamples {
                env = Float(n) / Float(attackSamples)
            } else {
                let tAfterAttack = Double(n - attackSamples) / sampleRate
                env = Float(exp(-tAfterAttack / decayConst))
            }

            let white = Float(rng.nextUnit() * 2.0 - 1.0)
            let noise = bandpass.process(white)
            let body = Float(sin(twoPiBodyOverSr * Double(n)))

            var s = (noise * noiseMix + body * bodyMix) * env * amplitude
            s = max(-1.0, min(1.0, s))   // 소프트 클램프
            out[n] = s
        }
        return out
    }
}
