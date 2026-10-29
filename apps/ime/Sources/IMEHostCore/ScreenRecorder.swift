import AVFoundation
import ScreenCaptureKit

enum ScreenRecorderError: Error, LocalizedError {
    case displayNotFound
    case cannotWrite(String)
    case noFrames

    var errorDescription: String? {
        switch self {
        case .displayNotFound: return "The display is no longer available"
        case .cannotWrite(let reason): return "Cannot write the video: \(reason)"
        case .noFrames: return "No frames were recorded"
        }
    }
}

/// What to record: an area of one display, at a size and frame rate, with or without sound, into an MP4 file.
struct ScreenRecordingRequest: Sendable, Equatable {
    let displayID: CGDirectDisplayID
    /// Display points with the origin at the top left (ScreenCaptureKit's `sourceRect`).
    let sourceRect: CGRect
    /// Encoded size in pixels; both even.
    let width: Int
    let height: Int
    let frameRate: Int
    /// Our own windows to leave out (the recording frame and its controls).
    let excludedWindowIDs: [CGWindowID]
    let url: URL
    /// Sound from apps, such as the other people in a meeting.
    var systemAudio = false
    /// The default input device; only honored from macOS 15 and with microphone access.
    var microphone = false

    var audioSources: [ScreenRecordingAudio.Source] {
        var sources: [ScreenRecordingAudio.Source] = []
        if systemAudio {
            sources.append(.system)
        }
        if microphone, ScreenRecordingAudio.microphoneSupported {
            sources.append(.microphone)
        }
        return sources
    }
}

/// Records one display area to an MP4 file: ScreenCaptureKit delivers frames, AVAssetWriter encodes them
/// with H.264. With sound on, system audio and the microphone arrive on the same queue, are mixed
/// (`ScreenRecordingAudioMixer`) and encoded as one AAC track. Everything is handled on a private queue
/// and never touches the main actor. The file is written in 2-second fragments, so a recording cut off
/// by a crash or a write error still plays up to the last fragment. Fragments need the encoder to keep frames in order (no B-frames): with reordering on, the
/// writer failed at a fragment now and then (AVFoundation -11800, MovieHeaderMaker -16341).
final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    /// How a recording ended.
    enum Ending: Equatable {
        case complete
        /// The writer failed; the file keeps what was written up to its last fragment.
        case cutShort(String)
    }

    /// Called once, on a private queue, when the stream stops on its own (display gone, access revoked)
    /// or the file cannot be written. `stop()` still has to be called to finish the file.
    private let onInterrupt: (@Sendable (Error) -> Void)?

    private let queue = DispatchQueue(label: "SmartIME.ScreenRecorder", qos: .userInitiated)
    private let request: ScreenRecordingRequest
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput?
    private var stream: SCStream?

    // Only touched on `queue`.
    private var sessionStarted = false
    private var finished = false
    private var interrupted = false
    private var lastTime = CMTime.invalid
    private var lastArrival = CMTime.invalid
    private(set) var frameCount = 0
    private var mixer: ScreenRecordingAudioMixer?
    private var converters: [ScreenRecordingAudio.Source: ScreenRecordingAudioConverter] = [:]
    /// Added to a source's timestamps; zero unless its clock turned out not to be the host clock.
    private var clockShifts: [ScreenRecordingAudio.Source: CMTime] = [:]
    /// Mixed frames written to the audio track.
    private(set) var audioFrameCount = 0

    /// Creates the file and the encoder; `start(_:onInterrupt:)` also starts capturing.
    init(request: ScreenRecordingRequest, onInterrupt: (@Sendable (Error) -> Void)? = nil) throws {
        self.request = request
        self.onInterrupt = onInterrupt
        do {
            writer = try AVAssetWriter(outputURL: request.url, fileType: .mp4)
        } catch {
            throw ScreenRecorderError.cannotWrite(Self.describe(error))
        }
        input = AVAssetWriterInput(mediaType: .video, outputSettings: Self.videoSettings(for: request))
        input.expectsMediaDataInRealTime = true
        writer.movieFragmentInterval = CMTime(seconds: 2, preferredTimescale: 600)
        guard writer.canAdd(input) else {
            throw ScreenRecorderError.cannotWrite("the video settings were refused")
        }
        writer.add(input)
        if request.audioSources.isEmpty {
            audioInput = nil
        } else {
            let audioInput = AVAssetWriterInput(
                mediaType: .audio, outputSettings: ScreenRecordingAudio.writerSettings,
                sourceFormatHint: ScreenRecordingAudio.format.formatDescription
            )
            audioInput.expectsMediaDataInRealTime = true
            guard writer.canAdd(audioInput) else {
                throw ScreenRecorderError.cannotWrite("the audio settings were refused")
            }
            writer.add(audioInput)
            self.audioInput = audioInput
            for source in request.audioSources {
                converters[source] = ScreenRecordingAudioConverter()
            }
        }
        guard writer.startWriting() else {
            throw ScreenRecorderError.cannotWrite(Self.describe(writer.error))
        }
        super.init()
    }

    /// Starts capturing; returns once the first frames are on their way.
    static func start(_ request: ScreenRecordingRequest, onInterrupt: @escaping @Sendable (Error) -> Void) async throws -> ScreenRecorder {
        let recorder = try ScreenRecorder(request: request, onInterrupt: onInterrupt)
        try await recorder.begin()
        return recorder
    }

    private func begin() async throws {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            discard()
            throw error
        }
        guard let display = content.displays.first(where: { $0.displayID == request.displayID }) else {
            discard()
            throw ScreenRecorderError.displayNotFound
        }
        let excluded = content.windows.filter { request.excludedWindowIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = request.sourceRect
        configuration.width = request.width
        configuration.height = request.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(request.frameRate))
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        configuration.colorMatrix = CGDisplayStream.yCbCrMatrix_ITU_R_709_2
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.showsCursor = true
        configuration.queueDepth = 6
        let sources = request.audioSources
        configuration.capturesAudio = sources.contains(.system)
        if sources.contains(.system) {
            configuration.sampleRate = Int(ScreenRecordingAudio.sampleRate)
            configuration.channelCount = 2
            configuration.excludesCurrentProcessAudio = true
        }
        if #available(macOS 15.0, *), sources.contains(.microphone) {
            configuration.captureMicrophone = true
        }

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            if sources.contains(.system) {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
            }
            if #available(macOS 15.0, *), sources.contains(.microphone) {
                try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue)
            }
            try await stream.startCapture()
        } catch {
            discard()
            throw error
        }
        self.stream = stream
    }

    /// Before any frame: drops the writer and the empty file.
    private func discard() {
        queue.sync {
            finished = true
        }
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: request.url)
    }

    /// Stops capturing and completes the file. The last frame lasts until the moment of the stop, so a
    /// still screen at the end is kept. After a write error the file is kept if it plays; it throws when
    /// nothing usable was written.
    @discardableResult
    func stop() async throws -> Ending {
        if let stream {
            self.stream = nil
            try? await stream.stopCapture()
        }
        let ending = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Ending, Error>) in
            queue.async {
                self.finish(continuation)
            }
        }
        if case .cutShort(let reason) = ending, await !Self.isPlayable(request.url) {
            try? FileManager.default.removeItem(at: request.url)
            throw ScreenRecorderError.cannotWrite(reason)
        }
        return ending
    }

    private func finish(_ continuation: CheckedContinuation<Ending, Error>) {
        guard !finished else {
            continuation.resume(returning: .complete)
            return
        }
        finished = true
        guard sessionStarted else {
            let error = writer.error
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: request.url)
            continuation.resume(throwing: error.map { ScreenRecorderError.cannotWrite(Self.describe($0)) } ?? ScreenRecorderError.noFrames)
            return
        }
        guard writer.status == .writing else {
            // The fragments written before the failure stay in the file.
            continuation.resume(returning: .cutShort(Self.describe(writer.error)))
            return
        }
        if let audioInput {
            writeAudio(flush: true)
            audioInput.markAsFinished()
        }
        input.markAsFinished()
        // Frame times and the host clock may not share a base, so the end is the last frame's time
        // plus how long ago it arrived.
        let sinceLast = CMTimeSubtract(Self.hostTime(), lastArrival)
        writer.endSession(atSourceTime: CMTimeAdd(lastTime, CMTimeMaximum(sinceLast, .zero)))
        writer.finishWriting {
            if self.writer.status == .completed {
                continuation.resume(returning: .complete)
            } else {
                continuation.resume(returning: .cutShort(Self.describe(self.writer.error)))
            }
        }
    }

    // MARK: SCStreamOutput, SCStreamDelegate

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen:
            append(sampleBuffer)
        case .audio:
            appendAudio(sampleBuffer, from: .system)
        default:
            if #available(macOS 15.0, *), type == .microphone {
                appendAudio(sampleBuffer, from: .microphone)
            }
        }
    }

    /// Writes one frame from the stream. Runs on the stream's queue; tests call it directly.
    func append(_ sampleBuffer: CMSampleBuffer) {
        guard !finished, sampleBuffer.isValid, Self.isCompleteFrame(sampleBuffer) else {
            return
        }
        guard writer.status == .writing else {
            interrupt(ScreenRecorderError.cannotWrite(Self.describe(writer.error)))
            return
        }
        let time = sampleBuffer.presentationTimeStamp
        if !sessionStarted {
            writer.startSession(atSourceTime: time)
            sessionStarted = true
            if audioInput != nil {
                mixer = ScreenRecordingAudioMixer(origin: time, sources: request.audioSources)
            }
        } else if CMTimeCompare(time, lastTime) <= 0 {
            return
        }
        // A frame the encoder has no room for is dropped; the previous one simply lasts longer.
        guard input.isReadyForMoreMediaData, input.append(sampleBuffer) else {
            return
        }
        lastTime = time
        lastArrival = Self.hostTime()
        frameCount += 1
    }

    /// Adds one buffer of sound to the mix and writes what is ready. Sound before the first frame is
    /// dropped: the video sets the start. Runs on the stream's queue; tests call it directly.
    func appendAudio(_ sampleBuffer: CMSampleBuffer, from source: ScreenRecordingAudio.Source) {
        guard !finished, sessionStarted, let mixer, sampleBuffer.isValid,
              let pcm = ScreenRecordingAudio.pcmBuffer(sampleBuffer),
              let samples = converters[source]?.convert(pcm) else {
            return
        }
        mixer.add(left: samples.left, right: samples.right, at: hostTime(of: sampleBuffer, from: source), from: source)
        writeAudio(flush: false)
    }

    /// ScreenCaptureKit stamps sound with the host clock, like the frames. Should a source's first buffer be
    /// more than a second off the host clock, that source is taken to run on its own clock and is lined up
    /// by when its first buffer arrived, rather than being dropped as out of range.
    private func hostTime(of sampleBuffer: CMSampleBuffer, from source: ScreenRecordingAudio.Source) -> CMTime {
        let time = sampleBuffer.presentationTimeStamp
        if clockShifts[source] == nil {
            let now = Self.hostTime()
            let lag = CMTimeSubtract(now, time)
            clockShifts[source] = abs(lag.seconds) > 1
                ? CMTimeSubtract(CMTimeSubtract(now, sampleBuffer.duration.isNumeric ? sampleBuffer.duration : .zero), time)
                : .zero
        }
        return CMTimeAdd(time, clockShifts[source] ?? .zero)
    }

    /// Hands the mixed sound to the encoder. When the encoder is busy the sound waits in the mixer; at the
    /// end it is given up to half a second to take the rest.
    private func writeAudio(flush: Bool) {
        guard let audioInput, let mixer else {
            return
        }
        var waited = 0
        while writer.status == .writing {
            guard audioInput.isReadyForMoreMediaData else {
                guard flush, waited < 50 else {
                    return
                }
                waited += 1
                usleep(10_000)
                continue
            }
            guard let chunk = mixer.take(flush: flush),
                  let sample = ScreenRecordingAudio.sampleBuffer(chunk.buffer, at: chunk.time) else {
                return
            }
            if audioInput.append(sample) {
                audioFrameCount += Int(chunk.buffer.frameLength)
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async {
            self.interrupt(error)
        }
    }

    private func interrupt(_ error: Error) {
        guard !interrupted else {
            return
        }
        interrupted = true
        onInterrupt?(error)
    }

    // MARK: Helpers

    /// Whether AVFoundation reads a video track with some duration from `url`.
    static func isPlayable(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty,
              let duration = try? await asset.load(.duration) else {
            return false
        }
        return duration.seconds > 0
    }

    /// Only complete frames carry a new image; idle frames (nothing changed) are skipped.
    private static func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else {
            return false
        }
        return status == .complete
    }

    /// The message with its domain and code, and the underlying status, which says more than AVFoundation's
    /// "The operation could not be completed".
    static func describe(_ error: Error?) -> String {
        guard let error = error as NSError? else {
            return "unknown error"
        }
        var text = "\(error.localizedDescription) (\(error.domain) \(error.code)"
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            text += ", \(underlying.domain) \(underlying.code)"
        }
        return text + ")"
    }

    private static func hostTime() -> CMTime {
        CMClockGetTime(CMClockGetHostTimeClock())
    }

    /// About 0.08 bits per pixel per frame (5 Mbit/s for 1080p at 30 fps), from 2 to 24 Mbit/s. Screen
    /// content is mostly still, so the encoder rarely needs the whole budget.
    static func bitRate(width: Int, height: Int, frameRate: Int) -> Int {
        let estimate = Double(width * height * frameRate) * 0.08
        return Int(min(max(estimate, 2_000_000), 24_000_000))
    }

    static func videoSettings(for request: ScreenRecordingRequest) -> [String: Any] {
        [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: request.width,
            AVVideoHeightKey: request.height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate(width: request.width, height: request.height, frameRate: request.frameRate),
                AVVideoExpectedSourceFrameRateKey: request.frameRate,
                AVVideoMaxKeyFrameIntervalKey: request.frameRate * 2,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoAllowFrameReorderingKey: false,
            ],
        ]
    }
}
