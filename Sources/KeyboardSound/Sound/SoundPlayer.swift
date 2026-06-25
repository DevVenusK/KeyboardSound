import AVFoundation

/// 버퍼 재생 추상화. 테스트에서 스파이로 대체 가능.
protocol SoundPlaying: AnyObject {
    func play(_ buffer: AVAudioPCMBuffer, volume: Float)
}

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

    func start() throws {
        guard !engine.isRunning else { return }
        engine.prepare()
        try engine.start()
        players.forEach { $0.play() }
    }

    func stop() {
        players.forEach { $0.stop() }
        engine.stop()
    }

    func play(_ buffer: AVAudioPCMBuffer, volume: Float) {
        guard engine.isRunning else { return }
        let node = players[nextIndex]
        nextIndex = (nextIndex + 1) % players.count
        node.volume = max(0, min(1, volume))
        node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }
}
