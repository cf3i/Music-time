import Accelerate
import Combine
import Foundation

final class AudioAnalyzer: ObservableObject {
    @Published private(set) var spectrum = [Float](repeating: 0, count: 128)

    var smoothing: Float = 0.72

    private let fftSize = 2_048
    private let bandCount = 128
    private let sampleRate: Float = 48_000
    private let analysisQueue = DispatchQueue(label: "local.edgepulse.analysis", qos: .userInteractive)
    private var pendingSamples: [Float] = []
    private var smoothed = [Float](repeating: 0, count: 128)
    private var window: [Float]
    private var fftSetup: FFTSetup?

    init() {
        window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Float(fftSize))), FFTRadix(kFFTRadix2))
        pendingSamples.reserveCapacity(fftSize * 2)
    }

    deinit {
        if let fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
        }
    }

    func ingest(_ samples: [Float]) {
        guard !samples.isEmpty else { return }

        analysisQueue.async { [weak self] in
            guard let self else { return }
            self.pendingSamples.append(contentsOf: samples)

            while self.pendingSamples.count >= self.fftSize {
                let frame = Array(self.pendingSamples.prefix(self.fftSize))
                self.pendingSamples.removeFirst(self.fftSize)
                self.analyze(frame)
            }
        }
    }

    func reset() {
        analysisQueue.async { [weak self] in
            guard let self else { return }
            self.pendingSamples.removeAll(keepingCapacity: true)
            self.smoothed = [Float](repeating: 0, count: self.bandCount)
            DispatchQueue.main.async {
                self.spectrum = [Float](repeating: 0, count: self.bandCount)
            }
        }
    }

    private func analyze(_ frame: [Float]) {
        guard let fftSetup else { return }

        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(frame, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        let halfSize = fftSize / 2
        var real = [Float](repeating: 0, count: halfSize)
        var imaginary = [Float](repeating: 0, count: halfSize)
        var magnitudes = [Float](repeating: 0, count: halfSize)

        real.withUnsafeMutableBufferPointer { realBuffer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                var split = DSPSplitComplex(
                    realp: realBuffer.baseAddress!,
                    imagp: imaginaryBuffer.baseAddress!
                )

                windowed.withUnsafeBytes { rawBuffer in
                    let complex = rawBuffer.baseAddress!.assumingMemoryBound(to: DSPComplex.self)
                    vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(halfSize))
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
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(halfSize))
            }
        }

        var normalized = [Float](repeating: 0, count: bandCount)
        let minFrequency: Float = 45
        let maxFrequency: Float = 16_000
        let binWidth = sampleRate / Float(fftSize)
        let scale = 2 / Float(fftSize)

        for band in 0..<bandCount {
            let lowerRatio = Float(band) / Float(bandCount)
            let upperRatio = Float(band + 1) / Float(bandCount)
            let lowerFrequency = minFrequency * pow(maxFrequency / minFrequency, lowerRatio)
            let upperFrequency = minFrequency * pow(maxFrequency / minFrequency, upperRatio)
            let lowerBin = max(1, min(halfSize - 1, Int(lowerFrequency / binWidth)))
            let upperBin = max(lowerBin + 1, min(halfSize, Int(ceil(upperFrequency / binWidth))))

            var peak: Float = 0
            for bin in lowerBin..<upperBin {
                peak = max(peak, magnitudes[bin] * scale)
            }

            let compressed = log1p(peak * 90) / log1p(90)
            normalized[band] = min(1, max(0, compressed * 1.28))
        }

        let requestedSmoothing = min(0.95, max(0, smoothing))
        for index in 0..<bandCount {
            let target = normalized[index]
            let previous = smoothed[index]
            let keep = target > previous
                ? min(0.32, requestedSmoothing * 0.34)
                : max(0.08, requestedSmoothing)
            smoothed[index] = previous * keep + target * (1 - keep)
        }

        let output = smoothed
        DispatchQueue.main.async { [weak self] in
            self?.spectrum = output
        }
    }
}
