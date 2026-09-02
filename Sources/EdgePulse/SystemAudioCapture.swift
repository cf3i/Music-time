import AudioToolbox
import CoreAudio
import CoreGraphics
import CoreMedia
import Foundation
import OSLog
@preconcurrency import ScreenCaptureKit

final class SystemAudioCapture {
    enum State: Sendable {
        case idle
        case starting
        case running
        case permissionRequired
        case failed(String)
    }

    private let backend: any AudioCaptureBackend

    var onSamples: (@Sendable ([Float], Float) -> Void)? {
        get { backend.onSamples }
        set { backend.onSamples = newValue }
    }

    var onStateChange: (@Sendable (State) -> Void)? {
        get { backend.onStateChange }
        set { backend.onStateChange = newValue }
    }

    init() {
        if #available(macOS 14.2, *) {
            backend = CoreAudioTapBackend()
        } else {
            backend = ScreenCaptureAudioBackend()
        }
    }

    func start() {
        backend.start()
    }

    func stop() {
        backend.stop()
    }

    func restart() {
        backend.restart()
    }
}

private protocol AudioCaptureBackend: AnyObject {
    var onSamples: (@Sendable ([Float], Float) -> Void)? { get set }
    var onStateChange: (@Sendable (SystemAudioCapture.State) -> Void)? { get set }

    func start()
    func stop()
    func restart()
}

private final class ScreenCaptureAudioBackend: NSObject, AudioCaptureBackend, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    var onSamples: (@Sendable ([Float], Float) -> Void)?
    var onStateChange: (@Sendable (SystemAudioCapture.State) -> Void)?

    private let sampleQueue = DispatchQueue(label: "com.cf3i.edgepulse.audio", qos: .userInteractive)
    private let controlQueue = DispatchQueue(label: "com.cf3i.edgepulse.capture-control", qos: .userInitiated)
    private let bufferListCapacity = 8
    private let bufferListByteCount: Int
    private let bufferListStorage: UnsafeMutableRawPointer
    private var lifecycle = CaptureLifecycle()
    private var stream: SCStream?
    private var streamGeneration: UInt64?
    private var startTask: Task<Void, Never>?

    override init() {
        bufferListByteCount = MemoryLayout<AudioBufferList>.size
            + MemoryLayout<AudioBuffer>.stride * (bufferListCapacity - 1)
        bufferListStorage = UnsafeMutableRawPointer.allocate(
            byteCount: bufferListByteCount,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        let pointer = bufferListStorage.bindMemory(to: AudioBufferList.self, capacity: 1)
        pointer.initialize(
            to: AudioBufferList(
                mNumberBuffers: 0,
                mBuffers: AudioBuffer(mNumberChannels: 0, mDataByteSize: 0, mData: nil)
            )
        )
        super.init()
    }

    deinit {
        bufferListStorage.deallocate()
    }

    func start() {
        controlQueue.async { [weak self] in
            guard let self,
                  let token = self.lifecycle.requestStart() else {
                return
            }

            self.emit(.starting)
            let task = Task<Void, Never> { [weak self] in
                guard let self else { return }
                await self.startCapture(generation: token)
            }
            self.startTask = task
        }
    }

    func stop() {
        controlQueue.async { [weak self] in
            guard let self else { return }

            self.lifecycle.requestStop()
            self.startTask?.cancel()
            self.startTask = nil

            let activeStream = self.stream
            self.stream = nil
            self.streamGeneration = nil
            self.emit(.idle)

            guard let activeStream else { return }
            Task {
                try? await activeStream.stopCapture()
            }
        }
    }

    func restart() {
        stop()
        start()
    }

    func stream(_ stoppedStream: SCStream, didStopWithError error: Error) {
        controlQueue.async { [weak self] in
            guard let self,
                  self.stream === stoppedStream,
                  let token = self.streamGeneration,
                  self.lifecycle.activeStreamStopped(token: token) else {
                return
            }

            self.stream = nil
            self.streamGeneration = nil
            self.emit(.failed(error.localizedDescription))
        }
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
        guard maximumBuffers <= bufferListCapacity else { return }

        let bufferListPointer = bufferListStorage.bindMemory(to: AudioBufferList.self, capacity: 1)
        bufferListPointer.pointee.mNumberBuffers = 0

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

        onSamples?(mono, Float(basicDescription.mSampleRate))
    }

    private func startCapture(generation token: UInt64) async {
        guard !Task.isCancelled, isCurrent(token) else { return }

        let hasPermission = await MainActor.run {
            CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
        }
        guard hasPermission else {
            controlQueue.async { [weak self] in
                guard let self,
                      self.lifecycle.permissionWasDenied(token: token) else {
                    return
                }
                self.startTask = nil
                self.emit(.permissionRequired)
            }
            return
        }

        do {
            let availableContent = try await SCShareableContent.excludingDesktopWindows(
                true,
                onScreenWindowsOnly: true
            )
            try Task.checkCancellation()
            guard isCurrent(token),
                  let display = preferredDisplay(from: availableContent.displays) else {
                return
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

            let candidateStream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try candidateStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
            try Task.checkCancellation()
            guard isCurrent(token) else { return }
            try await candidateStream.startCapture()

            controlQueue.async { [weak self] in
                guard let self else { return }
                self.startTask = nil

                guard self.lifecycle.didStart(token: token) else {
                    Task { try? await candidateStream.stopCapture() }
                    return
                }

                self.stream = candidateStream
                self.streamGeneration = token
                self.emit(.running)
            }
        } catch is CancellationError {
            // A newer start/stop intent superseded this work.
        } catch {
            controlQueue.async { [weak self] in
                guard let self else { return }

                let transitioned: Bool
                let state: SystemAudioCapture.State
                if self.isPermissionDenied(error) {
                    transitioned = self.lifecycle.permissionWasDenied(token: token)
                    state = .permissionRequired
                } else {
                    transitioned = self.lifecycle.didFail(token: token)
                    state = .failed(error.localizedDescription)
                }

                guard transitioned else { return }
                self.startTask = nil
                self.emit(state)
            }
        }
    }

    private func isPermissionDenied(_ error: Error) -> Bool {
        let cocoaError = error as NSError
        // SCStreamErrorUserDeclined is -3801 in ScreenCaptureKit.
        return cocoaError.domain == SCStreamErrorDomain && cocoaError.code == -3_801
    }

    private func isCurrent(_ token: UInt64) -> Bool {
        controlQueue.sync {
            lifecycle.accepts(token)
        }
    }

    private func emit(_ state: SystemAudioCapture.State) {
        onStateChange?(state)
    }

    private func preferredDisplay(from displays: [SCDisplay]) -> SCDisplay? {
        let mainDisplayID = CGMainDisplayID()
        return displays.first(where: { $0.displayID == mainDisplayID }) ?? displays.first
    }
}

@available(macOS 14.2, *)
private final class CoreAudioTapBackend: AudioCaptureBackend, @unchecked Sendable {
    var onSamples: (@Sendable ([Float], Float) -> Void)?
    var onStateChange: (@Sendable (SystemAudioCapture.State) -> Void)?

    private let controlQueue = DispatchQueue(label: "com.cf3i.edgepulse.core-audio-control", qos: .userInitiated)
    private let setupQueue = DispatchQueue(label: "com.cf3i.edgepulse.core-audio-setup", qos: .userInitiated)
    private let sampleQueue = DispatchQueue(label: "com.cf3i.edgepulse.core-audio-samples", qos: .userInteractive)
    private let logger = Logger(subsystem: "com.cf3i.edgepulse", category: "core-audio")
    private var lifecycle = CaptureLifecycle()
    private var session: CoreAudioTapSession?
    private var hasLoggedFirstBuffer = false

    func start() {
        controlQueue.async { [weak self] in
            guard let self,
                  let token = self.lifecycle.requestStart() else {
                return
            }

            self.emit(.starting)
            self.setupQueue.async { [weak self] in
                guard let self else { return }

                do {
                    let candidate = try self.makeSession()
                    self.controlQueue.async { [weak self] in
                        guard let self else {
                            candidate.stop()
                            return
                        }

                        guard self.lifecycle.didStart(token: token) else {
                            self.setupQueue.async {
                                candidate.stop()
                            }
                            return
                        }

                        self.session = candidate
                        self.emit(.running)
                    }
                } catch {
                    self.logger.error("Core Audio tap setup failed: \(error.localizedDescription, privacy: .public)")
                    self.controlQueue.async { [weak self] in
                        guard let self else { return }

                        let transitioned: Bool
                        let state: SystemAudioCapture.State
                        if (error as? CoreAudioTapError)?.isLikelyPermissionFailure == true {
                            transitioned = self.lifecycle.permissionWasDenied(token: token)
                            state = .permissionRequired
                        } else {
                            transitioned = self.lifecycle.didFail(token: token)
                            state = .failed(error.localizedDescription)
                        }

                        guard transitioned else { return }
                        self.emit(state)
                    }
                }
            }
        }
    }

    func stop() {
        controlQueue.async { [weak self] in
            guard let self else { return }

            self.lifecycle.requestStop()
            let activeSession = self.session
            self.session = nil
            self.emit(.idle)

            guard let activeSession else { return }
            self.setupQueue.async {
                activeSession.stop()
            }
        }
    }

    func restart() {
        stop()
        start()
    }

    private func makeSession() throws -> CoreAudioTapSession {
        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDescription.name = "EdgePulse System Audio"
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .unmuted

        var tapID = AudioObjectID(kAudioObjectUnknown)
        try check(
            AudioHardwareCreateProcessTap(tapDescription, &tapID),
            operation: .createTap
        )

        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        var ioProcID: AudioDeviceIOProcID?

        do {
            let tapUID = try tapUID(for: tapID)
            let tapFormat = try tapFormat(for: tapID)

            guard tapFormat.mFormatID == kAudioFormatLinearPCM,
                  tapFormat.mBitsPerChannel == 32,
                  tapFormat.mFormatFlags & kAudioFormatFlagIsFloat != 0 else {
                throw CoreAudioTapError.unsupportedFormat
            }

            let subTapDescription: [String: Any] = [
                kAudioSubTapUIDKey: tapUID,
                kAudioSubTapDriftCompensationKey: true
            ]
            let aggregateDescription: [String: Any] = [
                kAudioAggregateDeviceNameKey: "EdgePulse Capture",
                kAudioAggregateDeviceUIDKey: "com.cf3i.edgepulse.capture.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: false,
                kAudioAggregateDeviceTapListKey: [subTapDescription]
            ]
            try check(
                AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID),
                operation: .createAggregateDevice
            )

            let sampleRate = Float(tapFormat.mSampleRate)
            try check(
                AudioDeviceCreateIOProcIDWithBlock(
                    &ioProcID,
                    aggregateID,
                    sampleQueue
                ) { [weak self] _, inputData, _, _, _ in
                    self?.handle(inputData: inputData, sampleRate: sampleRate)
                },
                operation: .createIOProc
            )

            guard let ioProcID else {
                throw CoreAudioTapError.missingIOProc
            }
            try check(
                AudioDeviceStart(aggregateID, ioProcID),
                operation: .startIO
            )

            return CoreAudioTapSession(
                tapID: tapID,
                aggregateID: aggregateID,
                ioProcID: ioProcID
            )
        } catch {
            if let ioProcID {
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            if aggregateID != kAudioObjectUnknown {
                AudioHardwareDestroyAggregateDevice(aggregateID)
            }
            AudioHardwareDestroyProcessTap(tapID)
            throw error
        }
    }

    private func handle(
        inputData: UnsafePointer<AudioBufferList>,
        sampleRate: Float
    ) {
        let buffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: inputData)
        )
        guard !buffers.isEmpty else { return }

        var frameCount = Int.max
        var totalChannels = 0
        for buffer in buffers {
            let channelCount = max(1, Int(buffer.mNumberChannels))
            let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.stride * channelCount)
            frameCount = min(frameCount, frames)
            totalChannels += channelCount
        }

        guard frameCount > 0,
              frameCount != Int.max,
              totalChannels > 0 else {
            return
        }

        var mono = [Float](repeating: 0, count: frameCount)
        var channelsRead = 0

        for buffer in buffers {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                continue
            }

            let channelCount = max(1, Int(buffer.mNumberChannels))
            for frame in 0..<frameCount {
                let baseIndex = frame * channelCount
                for channel in 0..<channelCount {
                    mono[frame] += data[baseIndex + channel]
                }
            }
            channelsRead += channelCount
        }

        guard channelsRead > 0 else { return }
        if channelsRead > 1 {
            let divisor = Float(channelsRead)
            for frame in mono.indices {
                mono[frame] /= divisor
            }
        }

        if !hasLoggedFirstBuffer {
            hasLoggedFirstBuffer = true
            logger.info("Received first audio buffer: \(frameCount) frames at \(sampleRate, privacy: .public) Hz")
        }
        onSamples?(mono, sampleRate)
    }

    private func tapUID(for tapID: AudioObjectID) throws -> CFString {
        var address = propertyAddress(selector: kAudioTapPropertyUID)
        var value = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.stride)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, pointer)
        }
        try check(status, operation: .readProperty)
        return value
    }

    private func tapFormat(for tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
        var address = propertyAddress(selector: kAudioTapPropertyFormat)
        var value = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.stride)
        try check(
            AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &value),
            operation: .readProperty
        )
        return value
    }

    private func propertyAddress(
        selector: AudioObjectPropertySelector
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func check(_ status: OSStatus, operation: CoreAudioTapError.Operation) throws {
        guard status == noErr else {
            throw CoreAudioTapError.status(operation: operation, code: status)
        }
    }

    private func emit(_ state: SystemAudioCapture.State) {
        onStateChange?(state)
    }
}

@available(macOS 14.2, *)
private final class CoreAudioTapSession: @unchecked Sendable {
    private let lock = NSLock()
    private let tapID: AudioObjectID
    private let aggregateID: AudioObjectID
    private let ioProcID: AudioDeviceIOProcID
    private var isStopped = false

    init(
        tapID: AudioObjectID,
        aggregateID: AudioObjectID,
        ioProcID: AudioDeviceIOProcID
    ) {
        self.tapID = tapID
        self.aggregateID = aggregateID
        self.ioProcID = ioProcID
    }

    func stop() {
        lock.lock()
        guard !isStopped else {
            lock.unlock()
            return
        }
        isStopped = true
        lock.unlock()

        AudioDeviceStop(aggregateID, ioProcID)
        AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        AudioHardwareDestroyAggregateDevice(aggregateID)
        AudioHardwareDestroyProcessTap(tapID)
    }

    deinit {
        stop()
    }
}

@available(macOS 14.2, *)
private enum CoreAudioTapError: LocalizedError {
    enum Operation: String {
        case createTap = "create system-audio tap"
        case createAggregateDevice = "create private aggregate device"
        case readProperty = "read Core Audio property"
        case createIOProc = "create audio callback"
        case startIO = "start system-audio capture"
    }

    case status(operation: Operation, code: OSStatus)
    case unsupportedFormat
    case missingIOProc

    var isLikelyPermissionFailure: Bool {
        guard case .status(let operation, _) = self else { return false }
        return operation == .createTap || operation == .startIO
    }

    var errorDescription: String? {
        switch self {
        case .status(let operation, let code):
            return "Unable to \(operation.rawValue) (Core Audio status \(code), \(fourCharacterCode(code)))."
        case .unsupportedFormat:
            return "The system-audio tap returned an unsupported sample format."
        case .missingIOProc:
            return "Core Audio did not create an audio callback."
        }
    }

    private func fourCharacterCode(_ status: OSStatus) -> String {
        let value = UInt32(bitPattern: status)
        let bytes = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
        guard bytes.allSatisfy({ $0 >= 32 && $0 <= 126 }) else {
            return "non-printable"
        }
        return String(bytes: bytes, encoding: .ascii) ?? "non-printable"
    }
}
