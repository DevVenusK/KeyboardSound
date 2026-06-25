import Testing
@testable import KeyboardSound

@Test func sameSeedSameSequence() {
    var a = SplitMix64(seed: 42)
    var b = SplitMix64(seed: 42)
    for _ in 0..<100 { #expect(a.next() == b.next()) }
}

@Test func differentSeedDiffers() {
    var a = SplitMix64(seed: 1)
    var b = SplitMix64(seed: 2)
    #expect(a.next() != b.next())
}

@Test func nextUnitInRange() {
    var r = SplitMix64(seed: 7)
    for _ in 0..<1000 {
        let u = r.nextUnit()
        #expect(u >= 0.0 && u < 1.0)
    }
}

@Test func biquadProducesFiniteOutput() {
    var bp = BiquadBandpass(sampleRate: 44100, centerHz: 2000, q: 4.0)
    var r = SplitMix64(seed: 3)
    for _ in 0..<4410 {
        let y = bp.process(Float(r.nextUnit() * 2 - 1))
        #expect(y.isFinite)
        #expect(abs(y) < 100)   // 발산하지 않음
    }
}
