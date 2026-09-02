import Foundation
import XCTest
@testable import EdgePulse

final class SpectrumProcessorTests: XCTestCase {
    private let sampleRate: Float = 48_000

    func testLowMidAndHighTonesLandInAscendingBands() throws {
        let low = try dominantBand(for: 120)
        let mid = try dominantBand(for: 1_000)
        let high = try dominantBand(for: 8_000)

        XCTAssertLessThan(low.index, mid.index)
        XCTAssertLessThan(mid.index, high.index)
        XCTAssertGreaterThan(low.level, 0.1)
        XCTAssertGreaterThan(mid.level, 0.1)
        XCTAssertGreaterThan(high.level, 0.1)
    }

    func testSilenceDecaysSpectrum() throws {
        let processor = SpectrumProcessor()
        let tone = sineWave(frequency: 440, sampleCount: 12_288, sampleRate: sampleRate)
        let active = try XCTUnwrap(
            processor.process(samples: tone, sampleRate: sampleRate, smoothing: 0.85)
        )

        var silent: [Float]?
        for _ in 0..<24 {
            silent = processor.process(
                samples: [Float](repeating: 0, count: processor.hopSize),
                sampleRate: sampleRate,
                smoothing: 0.85
            )
        }

        let final = try XCTUnwrap(silent)
        XCTAssertLessThan(final.max() ?? 1, (active.max() ?? 0) * 0.08)
    }

    func testResetRequiresAFullWindowBeforePublishingAgain() throws {
        let processor = SpectrumProcessor()
        let initial = sineWave(frequency: 1_000, sampleCount: processor.fftSize, sampleRate: sampleRate)
        XCTAssertNotNil(processor.process(samples: initial, sampleRate: sampleRate, smoothing: 0))

        processor.reset()

        let partial = sineWave(
            frequency: 1_000,
            sampleCount: processor.fftSize - 1,
            sampleRate: sampleRate
        )
        XCTAssertNil(processor.process(samples: partial, sampleRate: sampleRate, smoothing: 0))
        XCTAssertNotNil(processor.process(samples: [0], sampleRate: sampleRate, smoothing: 0))
    }

    func testSampleRateChangeKeepsToneInSimilarBand() throws {
        let processor = SpectrumProcessor()
        let at48k = sineWave(frequency: 2_000, sampleCount: 12_288, sampleRate: 48_000)
        let spectrum48k = try XCTUnwrap(
            processor.process(samples: at48k, sampleRate: 48_000, smoothing: 0)
        )
        let band48k = try XCTUnwrap(spectrum48k.indices.max(by: { spectrum48k[$0] < spectrum48k[$1] }))

        processor.reset()
        let at44k = sineWave(frequency: 2_000, sampleCount: 12_288, sampleRate: 44_100)
        let spectrum44k = try XCTUnwrap(
            processor.process(samples: at44k, sampleRate: 44_100, smoothing: 0)
        )
        let band44k = try XCTUnwrap(spectrum44k.indices.max(by: { spectrum44k[$0] < spectrum44k[$1] }))

        XCTAssertLessThanOrEqual(abs(band48k - band44k), 2)
    }

    private func dominantBand(for frequency: Float) throws -> (index: Int, level: Float) {
        let processor = SpectrumProcessor()
        let samples = sineWave(frequency: frequency, sampleCount: 12_288, sampleRate: sampleRate)
        let spectrum = try XCTUnwrap(
            processor.process(samples: samples, sampleRate: sampleRate, smoothing: 0)
        )
        let index = try XCTUnwrap(spectrum.indices.max(by: { spectrum[$0] < spectrum[$1] }))
        return (index, spectrum[index])
    }

    private func sineWave(
        frequency: Float,
        sampleCount: Int,
        sampleRate: Float
    ) -> [Float] {
        (0..<sampleCount).map { sample in
            let phase = 2 * Float.pi * frequency * Float(sample) / sampleRate
            return sin(phase) * 0.8
        }
    }
}
