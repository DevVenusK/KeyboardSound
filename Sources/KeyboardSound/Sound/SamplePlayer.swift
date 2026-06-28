import AVFoundation
import os

private let sampleLog = Logger(subsystem: "com.keyboardsound.app", category: "sample")

/// 커스텀 샘플 재생 추상화. 테스트에서 스파이로 대체 가능.
protocol SamplePlaying: AnyObject {
    func playSample(_ buffer: AVAudioPCMBuffer, volume: Float)
}

/// 커스텀 샘플 전용 모노폰 재생기. 합성용 SoundPlayer와 **별도 엔진**을 사용해
/// 기존 합성 오디오 경로에 전혀 영향을 주지 않는다. 메인 스레드 전용.
final class SamplePlayer: SamplePlaying {
    let format: AVAudioFormat
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()

    init(sampleRate: Double = 44100) {
        self.format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    /// 엔진을 (필요 시) 시작. 멱등. 실패는 로깅.
    @discardableResult
    func start() -> Bool {
        guard !engine.isRunning else { return true }
        engine.prepare()
        do {
            try engine.start()
            node.play()
            return true
        } catch {
            sampleLog.error("SamplePlayer engine start failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func stop() {
        node.stop()
        engine.stop()
    }

    /// 이전 소리를 끊고(예약 버퍼 flush·시점 0) 처음부터 재생(모노폰).
    func playSample(_ buffer: AVAudioPCMBuffer, volume: Float) {
        if !engine.isRunning, !start() {
            sampleLog.error("playSample: engine not running and start() failed")
            return
        }
        node.stop()                                  // flush + sample-time reset
        node.volume = max(0, min(1, volume))
        node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        node.play()
    }
}
