import Testing
import AVFoundation
@testable import KeyboardSound

private let engineFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!

private func tempDir() -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("css-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

private func ephemeralDefaults() -> UserDefaults {
    UserDefaults(suiteName: "css-\(UUID().uuidString)")!
}

/// 48kHz 모노 WAV fixture — 디코딩 시 44.1kHz 스테레오로의 리샘플/채널 변환 경로를 강제.
private func writeFixtureWAV(seconds: Double = 0.1, sampleRate: Double = 48000) -> URL {
    let url = tempDir().appendingPathComponent("fixture.wav")
    let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let file = try! AVAudioFile(forWriting: url, settings: fmt.settings)
    let frames = AVAudioFrameCount(seconds * sampleRate)
    let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames)!
    buf.frameLength = frames
    let ch = buf.floatChannelData![0]
    for i in 0..<Int(frames) { ch[i] = sinf(Float(i) * 0.05) * 0.5 }
    try! file.write(from: buf)
    return url
}

@Test func importDecodesToEngineFormat() throws {
    let src = writeFixtureWAV()
    let store = CustomSampleStore(format: engineFormat, directory: tempDir(), defaults: ephemeralDefaults())
    try store.importFile(src)
    let buf = try #require(store.buffer)
    #expect(buf.frameLength > 0)
    #expect(buf.format.sampleRate == 44100)
    #expect(buf.format.channelCount == 2)
    #expect(store.fileName == "fixture.wav")
}

@Test func importBadFileThrows() {
    let bad = tempDir().appendingPathComponent("not-audio.wav")
    try! Data([0x00, 0x01, 0x02, 0x03]).write(to: bad)
    let store = CustomSampleStore(format: engineFormat, directory: tempDir(), defaults: ephemeralDefaults())
    #expect(throws: (any Error).self) { try store.importFile(bad) }
}

@Test func persistsAndReloadsAcrossInstances() throws {
    let dir = tempDir()
    let defs = ephemeralDefaults()
    let src = writeFixtureWAV()

    let store1 = CustomSampleStore(format: engineFormat, directory: dir, defaults: defs)
    try store1.importFile(src)

    let store2 = CustomSampleStore(format: engineFormat, directory: dir, defaults: defs)
    #expect(store2.buffer == nil)            // load 전엔 비어있음
    store2.loadPersisted()
    #expect(store2.buffer != nil)            // load 후 복원
    #expect(store2.fileName == "fixture.wav")
}

@Test func loadPersistedWithNothingIsNil() {
    let store = CustomSampleStore(format: engineFormat, directory: tempDir(), defaults: ephemeralDefaults())
    store.loadPersisted()
    #expect(store.buffer == nil)
}

@Test func loadPersistedWithMissingFileIsNil() {
    let dir = tempDir()
    let defs = ephemeralDefaults()
    let src = writeFixtureWAV()
    let store1 = CustomSampleStore(format: engineFormat, directory: dir, defaults: defs)
    try! store1.importFile(src)
    // 복사본을 지워 "파일 없음" 상황 재현
    try! FileManager.default.removeItem(at: dir)

    let store2 = CustomSampleStore(format: engineFormat, directory: dir, defaults: defs)
    store2.loadPersisted()
    #expect(store2.buffer == nil)            // 크래시 없이 무음
}
