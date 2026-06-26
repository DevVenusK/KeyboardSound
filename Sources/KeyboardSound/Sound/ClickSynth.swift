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

        // 클릭 트랜지언트 레이어 (청축 click jacket): 본체와 독립된 RNG/필터/빠른 감쇠.
        // 별도 RNG를 써서 clickAmount 변화가 본체 노이즈 시퀀스에 영향을 주지 않게 한다.
        let clickAmt = Float(parameters.clickAmount)
        var clickRng = SplitMix64(seed: seed ^ 0x9E37_79B9_7F4A_7C15)
        let clickHz = min(sampleRate * 0.45, 5000.0)          // 나이퀴스트 보호
        var clickBandpass = BiquadBandpass(sampleRate: sampleRate, centerHz: clickHz, q: 4.0)
        let clickDecayConst = max(0.0001, 0.004 / 5.0)        // ~4ms 매우 빠른 감쇠

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

            // 클릭 기여 (clickAmt==0이면 0, 기존 출력과 동일)
            var clickSample: Float = 0
            if clickAmt > 0 {
                let cWhite = Float(clickRng.nextUnit() * 2.0 - 1.0)
                let cFiltered = clickBandpass.process(cWhite)
                let cEnv = Float(exp(-Double(n) / sampleRate / clickDecayConst))
                clickSample = cFiltered * cEnv * clickAmt
            }

            var s = (noise * noiseMix + body * bodyMix) * env * amplitude + clickSample * amplitude
            s = max(-1.0, min(1.0, s))   // 소프트 클램프
            out[n] = s
        }
        return out
    }
}
