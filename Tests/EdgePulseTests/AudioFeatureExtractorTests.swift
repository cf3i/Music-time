import XCTest
@testable import EdgePulse

final class AudioFeatureExtractorTests: XCTestCase {
    func testFrequencyRegionsMapToIndependentFeatures() {
        let extractor = AudioFeatureExtractor()

        var bassSpectrum = [Float](repeating: 0.02, count: 128)
        for index in 0..<35 {
            bassSpectrum[index] = 0.8
        }
        let bass = extractor.process(bassSpectrum)

        XCTAssertGreaterThan(bass.bass, bass.mid * 10)
        XCTAssertGreaterThan(bass.kick, 0.8)

        extractor.reset()
        var highSpectrum = [Float](repeating: 0.02, count: 128)
        for index in 90..<128 {
            highSpectrum[index] = 0.75
        }
        let high = extractor.process(highSpectrum)

        XCTAssertGreaterThan(high.high, high.mid * 10)
        XCTAssertLessThan(high.kick, 0.2)
    }

    func testKickEnvelopeDecaysAndResetClearsMemory() {
        let extractor = AudioFeatureExtractor()
        var transient = [Float](repeating: 0, count: 128)
        for index in 0..<35 {
            transient[index] = 0.9
        }

        let initial = extractor.process(transient)
        var decayed = initial
        for _ in 0..<16 {
            decayed = extractor.process([Float](repeating: 0, count: 128))
        }

        XCTAssertGreaterThan(initial.kick, decayed.kick)
        XCTAssertLessThan(decayed.kick, 0.01)

        extractor.reset()
        let silent = extractor.process([Float](repeating: 0, count: 128))
        XCTAssertEqual(silent, .silent)
    }
}
