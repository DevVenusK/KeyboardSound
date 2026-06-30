import AVFoundation
import os

private let audioLog = Logger(subsystem: "com.keyboardsound.app", category: "audio")

/// 버퍼 재생 추상화. 테스트에서 스파이로 대체 가능.
protocol SoundPlaying: AnyObject {
    func play(_ buffer: AVAudioPCMBuffer, volume: Float)
}

/// 메인 스레드 전용. `play(_:volume:)`는 락 없이 `nextIndex`/노드 상태를 변경하므로
/// 반드시 메인 스레드(메인 런루프의 CGEventTap 콜백 경로)에서만 호출해야 한다.
///
/// AVAudioEngine + 플레이어 노드 풀(라운드로빈)로 겹치는 클릭음을 저지연 재생.
final class SoundPlayer: SoundPlaying {
    let format: AVAudioFormat
    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextIndex = 0

    init(poolSize: Int = 8, sampleRate: Double = 44100) {
        self.format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        for _ in 0..<max(1, poolSize) {
            let node = AVAudioPlayerNode()
            players.append(node)
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
        }
    }

    /// 엔진을 (필요 시) 시작한다. 멱등. 성공 여부를 반환하며 실패는 로깅한다.
    @discardableResult
    func start() -> Bool {
        guard !engine.isRunning else { return true }
        // 다른 앱(예: 애플뮤직 무손실)이 출력 장치 샘플레이트를 바꾸면 AVAudioEngine이
        // 정지하고 노드 연결이 무효화된다. 이때 start()만 하면 isRunning=true여도 무음이므로
        // (실측 확인) 시작 직전에 노드를 mainMixerNode에 다시 잇는다.
        for node in players {
            engine.connect(node, to: engine.mainMixerNode, format: format)
        }
        engine.prepare()
        do {
            try engine.start()
            players.forEach { $0.play() }
            return true
        } catch {
            audioLog.error("AVAudioEngine start failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func stop() {
        players.forEach { $0.stop() }
        engine.stop()
    }

    func play(_ buffer: AVAudioPCMBuffer, volume: Float) {
        let wasRunning = engine.isRunning
        // 엔진이 꺼져 있으면(런치 타이밍/라우트 변경/슬립 복귀 등) 재생 직전에 보장 시작.
        if !engine.isRunning, !start() {
            audioLog.error("play: engine not running and start() failed")
            return
        }
        let node = players[nextIndex]
        nextIndex = (nextIndex + 1) % players.count
        node.volume = max(0, min(1, volume))
        if !node.isPlaying { node.play() }
        node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        audioLog.debug("play wasRunning=\(wasRunning, privacy: .public) vol=\(volume, privacy: .public) len=\(buffer.frameLength, privacy: .public)")
    }
}
