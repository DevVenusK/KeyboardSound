import AVFoundation
import os

private let storeLog = Logger(subsystem: "com.keyboardsound.app", category: "sample")

/// 컨트롤러가 의존하는 버퍼 공급 추상화(테스트에서 스텁으로 대체 가능).
protocol SampleProviding: AnyObject {
    var buffer: AVAudioPCMBuffer? { get }
}

/// 사용자 오디오 파일을 앱 폴더로 복사·디코딩·영속화한다. 메인 스레드 전용.
final class CustomSampleStore: ObservableObject, SampleProviding {
    private enum Keys {
        static let path = "customSamplePath"
        static let name = "customSampleName"
    }

    @Published private(set) var fileName: String?
    private(set) var buffer: AVAudioPCMBuffer?

    private let format: AVAudioFormat
    private let directory: URL
    private let defaults: UserDefaults

    init(format: AVAudioFormat,
         directory: URL = CustomSampleStore.defaultDirectory,
         defaults: UserDefaults = .standard) {
        self.format = format
        self.directory = directory
        self.defaults = defaults
        self.fileName = defaults.string(forKey: Keys.name)
    }

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("KeyboardSound", isDirectory: true)
    }

    /// 파일 복사 + 디코딩 + 경로/이름 영속화. 디코딩 실패 시 throw하고 상태는 바뀌지 않는다.
    func importFile(_ url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = url.pathExtension.isEmpty ? "dat" : url.pathExtension
        let dst = directory.appendingPathComponent("custom-sample.\(ext)")
        if FileManager.default.fileExists(atPath: dst.path) {
            try FileManager.default.removeItem(at: dst)
        }
        try FileManager.default.copyItem(at: url, to: dst)

        // 디코딩 먼저 — 실패하면 복사본 정리하고 throw(이전 상태 유지).
        let decoded: AVAudioPCMBuffer
        do {
            decoded = try Self.decode(url: dst, to: format)
        } catch {
            try? FileManager.default.removeItem(at: dst)
            throw error
        }

        // 성공: 이전 복사본 제거 후 새 상태 커밋.
        if let old = defaults.string(forKey: Keys.path), old != dst.path {
            try? FileManager.default.removeItem(atPath: old)
        }
        buffer = decoded
        fileName = url.lastPathComponent
        defaults.set(dst.path, forKey: Keys.path)
        defaults.set(url.lastPathComponent, forKey: Keys.name)
    }

    /// 파일을 target 포맷의 PCM 버퍼로 디코딩(필요 시 리샘플/채널 변환).
    static func decode(url: URL, to target: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        let src = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0, let srcBuffer = AVAudioPCMBuffer(pcmFormat: src, frameCapacity: frames) else {
            throw NSError(domain: "CustomSampleStore", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "empty or unreadable audio"])
        }
        try file.read(into: srcBuffer)

        if src == target { return srcBuffer }

        guard let converter = AVAudioConverter(from: src, to: target) else {
            throw NSError(domain: "CustomSampleStore", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "no converter"])
        }
        let ratio = target.sampleRate / src.sampleRate
        let capacity = AVAudioFrameCount(Double(frames) * ratio) + 4096
        guard let dstBuffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            throw NSError(domain: "CustomSampleStore", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "alloc failed"])
        }
        var fed = false
        var convError: NSError?
        let status = converter.convert(to: dstBuffer, error: &convError) { _, outStatus in
            if fed { outStatus.pointee = .endOfStream; return nil }
            fed = true
            outStatus.pointee = .haveData
            return srcBuffer
        }
        if status == .error { throw convError ?? NSError(domain: "CustomSampleStore", code: 4) }
        guard dstBuffer.frameLength > 0 else {
            throw NSError(domain: "CustomSampleStore", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "conversion produced no frames"])
        }
        return dstBuffer
    }

    /// 저장된 경로에서 재디코딩(앱 시작 시). 실패/없음 → buffer = nil. (Task 3에서 구현)
    func loadPersisted() {}
}
