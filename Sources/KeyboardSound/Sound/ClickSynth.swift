import Foundation

/// 파라미터로부터 기계식 클릭음 PCM 샘플([Float])을 절차적으로 합성한다. 순수 함수.
///
/// 모델(연구 기반 — van den Doel & Pai FoleyAutomatic, Avanzini, Serra/Smith residual):
/// 닫힌형 사인("삐" 전자음) 대신 **여기 신호(짧은 노이즈 버스트=접촉력) → 비배음 공진기
/// 뱅크** 구조를 쓴다. 단일 클린 임펄스가 인공적으로 들린다는 결과를 반영해 여기를
/// 빠르게 감쇠하는 노이즈로 만들고, 광대역 트랜지언트(클랙)와 근접 디튜닝 모드(beating)를
/// 더해 사실감을 높인다. 마지막에 피크 정규화로 레벨을 안정화한다.
struct ClickSynth {
    let sampleRate: Double

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    func render(parameters: SoundParameters, phase: KeyPhase, pitchMultiplier: Double, seed: UInt64) -> [Float] {
        var rng = SplitMix64(seed: seed)
        let isUp = (phase == .up)

        // 릴리스(up)는 더 짧고 약하게.
        let decay = parameters.decayTime * (isUp ? 0.6 : 1.0)
        let amplitude: Float = isUp ? 0.5 : 1.0

        let count = max(1, Int(decay * sampleRate))
        var raw = [Float](repeating: 0, count: count)

        let toneHz = parameters.toneFrequency * pitchMultiplier
        let bodyHz = toneHz * 0.5
        let nyquist = sampleRate * 0.49
        let noiseMix = Float(1.0 - parameters.bodyMix)
        let bodyMix = Float(parameters.bodyMix)
        let humanize = parameters.humanization
        let sharp = max(0.0, min(1.0, parameters.sharpness))   // 어택 크리스프함 + 고역 함량
        let weight = max(0.0, min(1.0, parameters.weight))     // 저역 무게

        // ── 모달 공진기 뱅크 (비배음 비율). 각 모드 = 고-Q 밴드패스 공진기.
        //    Q는 목표 감쇠에서 역산(Q ≈ π·f·τ). 고차 모드일수록 빠르게 감쇠.
        // 모드: [서브(저역 무게), 기본, 비배음 고차×3]. 저역은 적당히 울려 "무게/통"을 주고,
        // 고차는 강하게 댐핑(낮은 Q·빠른 감쇠)해 "철판 통통" 금속 울림을 막는다.
        // 핵심: 금속성은 '고주파 고-Q 링'에서 오고, 무게는 '저역 링'에서 온다 → Q를 모드별로 분리.
        let ratios = [0.5, 1.0, 2.71, 5.15, 8.20]
        let gains: [Float] = [0.7, 1.2, 0.40, 0.16, 0.07]
        let decayScale = [0.9, 1.0, 0.40, 0.22, 0.14]
        let qCap = [55.0, 60.0, 22.0, 18.0, 15.0]
        var resonators: [BiquadBandpass] = []
        var resGains: [Float] = []
        for i in 0..<ratios.count {
            let f = min(bodyHz * ratios[i], nyquist)
            let tau = max(0.0006, decay * 0.75 * decayScale[i])
            let q = min(qCap[i], max(2.0, Double.pi * f * tau))
            // 무게(저역 모드 i<=1) / 샤프함(고역 모드 i>=2) 슬라이더로 모드 게인 조절. 0.5=중립(×1.0).
            let scale: Float = i <= 1 ? Float(0.6 + 0.8 * weight) : Float(0.5 + sharp)
            let g = gains[i] * scale
            resonators.append(BiquadBandpass(sampleRate: sampleRate, centerHz: f, q: q))
            resGains.append(g)
            // beating: 아주 미세한 디튜닝 짝 모드 (humanize>0).
            if humanize > 0 {
                let detune = 1.0 + (rng.nextUnit() - 0.5) * 0.006 * humanize
                resonators.append(BiquadBandpass(sampleRate: sampleRate, centerHz: min(f * detune, nyquist), q: q))
                resGains.append(g * 0.5)
            }
        }
        let resNorm = max(0.0001, resGains.reduce(0, +))
        let bodyGain: Float = 9.0   // 밴드패스 공진기 출력 보정(피크 정규화가 절대 레벨은 처리).

        // ── 여기 신호(접촉력): 짧고 빠르게 감쇠하는 노이즈 버스트. 단일 클린 임펄스가
        //    인공적이라는 결과 반영 — 광대역 마이크로-충돌로 모델링.
        // 샤프함이 클수록 여기 감쇠가 빨라 더 크리스프한 어택. (0.5=중립 ≈1.5ms)
        let excDecay = max(0.0004, 0.0026 - 0.0021 * Double(sharp))

        // ── 광대역 트랜지언트(클랙) 정형: 낮은 Q 밴드패스. 샤프함이 클수록 더 밝다. (0.5=중립 ≈1.5×)
        var transientBP = BiquadBandpass(sampleRate: sampleRate, centerHz: min(toneHz * (1.0 + Double(sharp)), nyquist), q: 0.7)

        // ── 클릭 자켓(청축): 본체와 독립된 RNG/필터/빠른 감쇠.
        let clickAmt = Float(parameters.clickAmount)
        var clickRng = SplitMix64(seed: seed ^ 0x9E37_79B9_7F4A_7C15)
        let clickHz = min(sampleRate * 0.45, 5000.0)
        var clickBandpass = BiquadBandpass(sampleRate: sampleRate, centerHz: clickHz, q: 4.0)
        let clickDecayConst = max(0.0001, 0.004 / 5.0)   // ~4ms

        // ── 버퍼 끝 짧은 페이드(꼬리 클릭 방지).
        let releaseSamples = max(1, Int(0.003 * sampleRate))

        var peak: Float = 1e-6
        for n in 0..<count {
            let nd = Double(n)

            // 여기 신호 e[n]
            let excEnv = Float(exp(-nd / sampleRate / excDecay))
            let e = Float(rng.nextUnit() * 2.0 - 1.0) * excEnv

            // 공진기 바디: 여기를 공진기 뱅크에 통과시켜 합산.
            var body: Float = 0
            for i in 0..<resonators.count {
                body += resGains[i] * resonators[i].process(e)
            }
            body = (body / resNorm) * bodyGain

            // 광대역 트랜지언트(클랙).
            let transient = transientBP.process(e)

            // 클릭 자켓 (clickAmt==0이면 0).
            var clickSample: Float = 0
            if clickAmt > 0 {
                let cWhite = Float(clickRng.nextUnit() * 2.0 - 1.0)
                let cEnv = Float(exp(-nd / sampleRate / clickDecayConst))
                clickSample = clickBandpass.process(cWhite) * cEnv * clickAmt
            }

            // 끝부분 페이드.
            var tail: Float = 1
            if n > count - releaseSamples {
                tail = Float(count - n) / Float(releaseSamples)
            }

            let s = (transient * noiseMix + body * bodyMix + clickSample) * tail
            raw[n] = s
            let a = abs(s)
            if a > peak { peak = a }
        }

        // 피크 정규화: 게인/믹스 불균형에 무관하게 일정 레벨로. up은 더 작게.
        var out = [Float](repeating: 0, count: count)
        let norm = (0.9 * amplitude) / peak
        for n in 0..<count {
            out[n] = max(-1.0, min(1.0, raw[n] * norm))
        }
        return out
    }
}
