import Accelerate
import Foundation

/// Synchronous, allocation-conscious FFT processor. All calls must come from one queue.
final class SpectrumProcessor {
    let fftSize: Int
    let hopSize: Int
    let bandCount: Int

    private var sampleRate: Float
    private var smoothing: Float = 0.72
    private var fftSetup: FFTSetup

    private var ring: [Float]
    private var ringWriteIndex = 0
    private var bufferedSampleCount = 0
    private var samplesSinceAnalysis = 0

    private var window: [Float]
    private var frame: [Float]
    private var windowed: [Float]
    private var real: [Float]
    private var imaginary: [Float]
    private var magnitudes: [Float]
    private var normalized: [Float]
    private var smoothed: [Float]
    private var bandRanges: [Range<Int>] = []
    private var adaptiveGain: Float = 1

    init(
        fftSize: Int = 4_096,
        hopSize: Int = 1_024,
        bandCount: Int = 128,
        sampleRate: Float = 48_000
    ) {
        precondition(fftSize.isPowerOfTwo)
        precondition(hopSize > 0 && hopSize <= fftSize)
        precondition(bandCount > 0 && bandCount < fftSize / 2)

        self.fftSize = fftSize
        self.hopSize = hopSize
        self.bandCount = bandCount
        self.sampleRate = sampleRate

        let log2n = vDSP_Length(log2(Float(fftSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            preconditionFailure("Unable to create FFT setup")
        }
        fftSetup = setup

        ring = [Float](repeating: 0, count: fftSize)
        window = [Float](repeating: 0, count: fftSize)
        frame = [Float](repeating: 0, count: fftSize)
        windowed = [Float](repeating: 0, count: fftSize)
        real = [Float](repeating: 0, count: fftSize / 2)
        imaginary = [Float](repeating: 0, count: fftSize / 2)
        magnitudes = [Float](repeating: 0, count: fftSize / 2)
        normalized = [Float](repeating: 0, count: bandCount)
        smoothed = [Float](repeating: 0, count: bandCount)

        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        rebuildBandRanges()
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    /// Returns the newest spectrum if this batch crossed one or more analysis hops.
    func process(
        samples: [Float],
        sampleRate: Float,
        smoothing: Float,
        automaticGain: Bool = false
    ) -> [Float]? {
        guard !samples.isEmpty else { return nil }
        updateConfiguration(sampleRate: sampleRate, smoothing: smoothing)

        var didAnalyze = false
        for sample in samples {
            ring[ringWriteIndex] = sample
            ringWriteIndex = (ringWriteIndex + 1) % fftSize
            bufferedSampleCount = min(fftSize, bufferedSampleCount + 1)
            samplesSinceAnalysis += 1

            guard bufferedSampleCount == fftSize,
                  samplesSinceAnalysis >= hopSize else {
                continue
            }

            samplesSinceAnalysis = 0
            copyChronologicalFrame()
            analyzeCurrentFrame(automaticGain: automaticGain)
            didAnalyze = true
        }
        return didAnalyze ? smoothed : nil
    }

    func reset() {
        ringWriteIndex = 0
        bufferedSampleCount = 0
        samplesSinceAnalysis = 0
        ring.withUnsafeMutableBufferPointer {
            $0.baseAddress?.update(repeating: 0, count: $0.count)
        }
        smoothed.withUnsafeMutableBufferPointer {
            $0.baseAddress?.update(repeating: 0, count: $0.count)
        }
        normalized.withUnsafeMutableBufferPointer {
            $0.baseAddress?.update(repeating: 0, count: $0.count)
        }
        adaptiveGain = 1
    }

    private func updateConfiguration(sampleRate: Float, smoothing: Float) {
        let safeRate = max(8_000, sampleRate)
        if abs(self.sampleRate - safeRate) > 0.5 {
            self.sampleRate = safeRate
            rebuildBandRanges()
        }
        self.smoothing = min(0.95, max(0, smoothing))
    }

    private func copyChronologicalFrame() {
        let tailCount = fftSize - ringWriteIndex
        for index in 0..<tailCount {
            frame[index] = ring[ringWriteIndex + index]
        }
        if ringWriteIndex > 0 {
            for index in 0..<ringWriteIndex {
                frame[tailCount + index] = ring[index]
            }
        }
    }

    private func analyzeCurrentFrame(automaticGain: Bool) {
        var meanSquare: Float = 0
        vDSP_measqv(frame, 1, &meanSquare, vDSP_Length(fftSize))
        if meanSquare < 0.000_000_006_4 {
            normalized.withUnsafeMutableBufferPointer {
                $0.baseAddress?.update(repeating: 0, count: $0.count)
            }
            adaptiveGain = 1
            applySmoothing()
            return
        }

        vDSP_vmul(frame, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        real.withUnsafeMutableBufferPointer { realBuffer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                var split = DSPSplitComplex(
                    realp: realBuffer.baseAddress!,
                    imagp: imaginaryBuffer.baseAddress!
                )

                windowed.withUnsafeBytes { rawBuffer in
                    let complex = rawBuffer.baseAddress!.assumingMemoryBound(to: DSPComplex.self)
                    vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(fftSize / 2))
                }

                vDSP_fft_zrip(
                    fftSetup,
                    &split,
                    1,
                    vDSP_Length(log2(Float(fftSize))),
                    FFTDirection(kFFTDirection_Forward)
                )
                realBuffer[0] = 0
                imaginaryBuffer[0] = 0
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }

        let magnitudeScale = 2 / Float(fftSize)
        for band in 0..<bandCount {
            let range = bandRanges[band]
            var peak: Float = 0
            var energy: Float = 0

            for bin in range {
                let magnitude = magnitudes[bin] * magnitudeScale
                peak = max(peak, magnitude)
                energy += magnitude * magnitude
            }

            let rms = sqrt(energy / Float(max(1, range.count)))
            let weightedMagnitude = peak * 0.72 + rms * 0.28
            let compressed = log1p(weightedMagnitude * 90) / log1p(90)
            normalized[band] = min(1, max(0, compressed * 1.28))
        }

        if automaticGain {
            let framePeak = normalized.max() ?? 0
            let targetGain = min(3.6, max(0.72, 0.74 / max(0.035, framePeak)))
            let response: Float = targetGain < adaptiveGain ? 0.48 : 0.055
            adaptiveGain += (targetGain - adaptiveGain) * response
        } else {
            adaptiveGain = 1
        }

        if adaptiveGain != 1 {
            for index in 0..<bandCount {
                normalized[index] = min(1, normalized[index] * adaptiveGain)
            }
        }

        applySmoothing()
    }

    private func applySmoothing() {
        for index in 0..<bandCount {
            let target = normalized[index]
            let previous = smoothed[index]
            let keep = target > previous
                ? min(0.32, smoothing * 0.34)
                : max(0.08, smoothing)
            smoothed[index] = previous * keep + target * (1 - keep)
        }
    }

    private func rebuildBandRanges() {
        let nyquistBin = fftSize / 2 - 1
        let binWidth = sampleRate / Float(fftSize)
        let minimumBin = max(1, Int(35 / binWidth))
        let maximumFrequency = min(16_000, sampleRate * 0.46)
        let maximumBin = min(nyquistBin, max(minimumBin + bandCount, Int(maximumFrequency / binWidth)))
        let minimumFrequency = Float(minimumBin) * binWidth
        let frequencyRatio = maximumFrequency / minimumFrequency

        var boundaries = [Int](repeating: minimumBin, count: bandCount + 1)
        for index in 0...bandCount {
            let progress = Float(index) / Float(bandCount)
            let frequency = minimumFrequency * pow(frequencyRatio, progress)
            boundaries[index] = min(maximumBin, max(minimumBin, Int(frequency / binWidth)))
        }

        boundaries[0] = minimumBin
        for index in 1...bandCount {
            boundaries[index] = max(boundaries[index], boundaries[index - 1] + 1)
        }
        boundaries[bandCount] = maximumBin
        if bandCount > 1 {
            for index in stride(from: bandCount - 1, through: 1, by: -1) {
                boundaries[index] = min(boundaries[index], boundaries[index + 1] - 1)
            }
        }

        bandRanges = (0..<bandCount).map { boundaries[$0]..<boundaries[$0 + 1] }
    }
}

private extension Int {
    var isPowerOfTwo: Bool {
        self > 0 && (self & (self - 1)) == 0
    }
}
