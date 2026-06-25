import AVFoundation

/// 메인 스레드 전용. `buffer(forKeyCode:phase:)`는 `pressCounters`를 변경하고
/// `regenerate(...)`는 `buffers`를 교체하므로, 두 메서드 모두 메인 스레드에서만 호출해야 한다.
///
/// 그룹/페이즈별 변형 버퍼를 사전 렌더하고, keyCode로 적절한 버퍼를 선택한다.
final class ClickSoundBank {
    private let format: AVAudioFormat
    private let sampleRate: Double
    private let variantCount: Int

    private var buffers: [KeyGroup: [KeyPhase: [AVAudioPCMBuffer]]] = [:]
    private var pressCounters: [Int: Int] = [:]

    init(format: AVAudioFormat, tone: Double, sharpness: Double, preset: Preset, variantCount: Int = 6) {
        self.format = format
        self.sampleRate = format.sampleRate
        self.variantCount = max(1, variantCount)
        regenerate(tone: tone, sharpness: sharpness, preset: preset)
    }

    /// 파라미터 변경 시 전체 버퍼 재생성.
    func regenerate(tone: Double, sharpness: Double, preset: Preset) {
        let synth = ClickSynth(sampleRate: sampleRate)
        var newBuffers: [KeyGroup: [KeyPhase: [AVAudioPCMBuffer]]] = [:]

        for group in [KeyGroup.normal, .wide] {
            let toneFreq = SoundParameterMapping.toneFrequency(tone: tone, group: group)
            // wide 키(스페이스 등)는 더 묵직하고 긴 감쇠 → decay 1.5배 적용
            let decayMultiplier = group == .wide ? 1.5 : 1.0
            let params = SoundParameters(
                toneFrequency: toneFreq,
                sharpness: sharpness,
                decayTime: preset.decayTime * decayMultiplier,
                bodyMix: preset.bodyMix,
                humanization: preset.humanization
            )

            var byPhase: [KeyPhase: [AVAudioPCMBuffer]] = [:]
            for phase in [KeyPhase.down, .up] {
                var variants: [AVAudioPCMBuffer] = []
                for i in 0..<variantCount {
                    // (group, phase, i) 결정적 시드
                    let groupComponent = UInt64(group == .wide ? 1 : 0) &* 1_000_003
                    let phaseComponent = UInt64(phase == .up ? 1 : 0) &* 7_919
                    let seed = groupComponent &+ phaseComponent &+ UInt64(i) &* 104_729 &+ 0xABCDEF

                    // 변형마다 미세 피치 지터 (휴머나이즈)
                    let spread = (Double(i) / Double(max(1, variantCount - 1))) - 0.5
                    let pitchMul = 1.0 + spread * 2.0 * params.humanization * 0.1

                    let samples = synth.render(parameters: params, phase: phase, pitchMultiplier: pitchMul, seed: seed)
                    variants.append(Self.makeBuffer(samples: samples, format: format))
                }
                byPhase[phase] = variants
            }
            newBuffers[group] = byPhase
        }
        buffers = newBuffers
    }

    /// keyCode와 페이즈로 버퍼 선택. down일 때 키별 카운터를 올려 변형을 순환시킨다.
    func buffer(forKeyCode keyCode: Int, phase: KeyPhase) -> AVAudioPCMBuffer {
        let group = KeyGroupMap.group(for: keyCode)
        let count = pressCounters[keyCode, default: 0]
        if phase == .down {
            pressCounters[keyCode] = count + 1
        }
        let index = abs(keyCode + count) % variantCount
        // 그룹/페이즈 버퍼는 init/regenerate에서 항상 채워지므로 강제 언랩 안전.
        return buffers[group]![phase]![index]
    }

    private static func makeBuffer(samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(samples.count)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        guard let channels = buffer.floatChannelData else { return buffer }
        let channelCount = Int(format.channelCount)
        for ch in 0..<channelCount {
            let dst = channels[ch]
            for i in 0..<samples.count { dst[i] = samples[i] }
        }
        return buffer
    }
}
