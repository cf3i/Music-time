import AppKit
import AudioToolbox
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    enum State {
        case idle
        case starting
        case running
        case permissionRequired
        case failed(String)
    }

    var onSamples: (([Float]) -> Void)?
    var onStateChange: ((State) -> Void)?

    private let sampleQueue = DispatchQueue(label: "local.edgepulse.audio", qos: .userInteractive)
    private var stream: SCStream?
    private var isStarting = false

    func start() {
        guard stream == nil, !isStarting else { return }
        isStarting = true
        onStateChange?(.starting)

        Task { [weak self] in
            guard let self else { return }

            guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
                self.isStarting = false
                self.onStateChange?(.permissionRequired)
                return
            }

            do {
                let availableContent = try await SCShareableContent.excludingDesktopWindows(
                    true,
                    onScreenWindowsOnly: true
                )
                guard let display = self.preferredDisplay(from: availableContent.displays) else {
                    throw CaptureError.noDisplay
                }

                let filter = SCContentFilter(
                    display: display,
                    excludingApplications: [],
                    exceptingWindows: []
                )
                let configuration = SCStreamConfiguration()
                configuration.capturesAudio = true
                configuration.excludesCurrentProcessAudio = true
                configuration.sampleRate = 48_000
                configuration.channelCount = 2
                configuration.width = 2
                configuration.height = 2
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: 2)
                configuration.queueDepth = 3
                configuration.showsCursor = false

                let newStream = SCStream(filter: filter, configuration: configuration, delegate: self)
                try newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: self.sampleQueue)
                try await newStream.startCapture()

                self.stream = newStream
                self.isStarting = false
                self.onStateChange?(.running)
            } catch {
                self.isStarting = false
                self.stream = nil
                self.onStateChange?(.failed(error.localizedDescription))
            }
        }
    }

    func stop() {
        isStarting = false
        guard let activeStream = stream else {
            onStateChange?(.idle)
            return
        }
        stream = nil

        Task { [weak self] in
            do {
                try await activeStream.stopCapture()
            } catch {
                // The stream may already have stopped as part of shutdown.
            }
            self?.onStateChange?(.idle)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        self.stream = nil
        isStarting = false
        onStateChange?(.failed(error.localizedDescription))
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio,
              sampleBuffer.isValid,
              CMSampleBufferDataIsReady(sampleBuffer),
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let basicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee,
              basicDescription.mFormatID == kAudioFormatLinearPCM,
              basicDescription.mBitsPerChannel == 32,
              basicDescription.mFormatFlags & kAudioFormatFlagIsFloat != 0 else {
            return
        }

        let maximumBuffers = Int(max(1, basicDescription.mChannelsPerFrame))
        let bufferListByteCount = MemoryLayout<AudioBufferList>.size
            + MemoryLayout<AudioBuffer>.stride * (maximumBuffers - 1)
        let bufferListStorage = UnsafeMutableRawPointer.allocate(
            byteCount: bufferListByteCount,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferListStorage.deallocate() }

        let bufferListPointer = bufferListStorage.bindMemory(to: AudioBufferList.self, capacity: 1)
        bufferListPointer.initialize(
            to: AudioBufferList(
                mNumberBuffers: 0,
                mBuffers: AudioBuffer(mNumberChannels: 0, mDataByteSize: 0, mData: nil)
            )
        )

        var retainedBlockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: bufferListPointer,
            bufferListSize: bufferListByteCount,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            blockBufferOut: &retainedBlockBuffer
        )
        guard status == noErr else { return }

        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        let channelCount = Int(max(1, basicDescription.mChannelsPerFrame))
        var mono = [Float](repeating: 0, count: frameCount)

        if bufferList.count == 1,
           let data = bufferList[0].mData?.assumingMemoryBound(to: Float.self) {
            let channelsInBuffer = max(1, Int(bufferList[0].mNumberChannels))
            for frame in 0..<frameCount {
                var sum: Float = 0
                for channel in 0..<channelsInBuffer {
                    sum += data[frame * channelsInBuffer + channel]
                }
                mono[frame] = sum / Float(channelsInBuffer)
            }
        } else {
            let usableChannels = min(channelCount, bufferList.count)
            for channel in 0..<usableChannels {
                guard let data = bufferList[channel].mData?.assumingMemoryBound(to: Float.self) else {
                    continue
                }
                for frame in 0..<frameCount {
                    mono[frame] += data[frame]
                }
            }
            if usableChannels > 1 {
                let divisor = Float(usableChannels)
                for frame in 0..<frameCount {
                    mono[frame] /= divisor
                }
            }
        }

        onSamples?(mono)
    }

    private func preferredDisplay(from displays: [SCDisplay]) -> SCDisplay? {
        let mainDisplayID = (NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
            .uint32Value
        return displays.first(where: { $0.displayID == mainDisplayID }) ?? displays.first
    }
}

private enum CaptureError: LocalizedError {
    case noDisplay

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            return "No active display was found."
        }
    }
}
