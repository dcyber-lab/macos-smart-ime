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

/// What to record: an area of one display, at a size and frame rate, into an MP4 file.
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
}

/// Records one display area to an MP4 file: ScreenCaptureKit delivers frames, AVAssetWriter encodes them
/// with H.264. Frames are handled on a private queue and never touch the main actor. The file is not
/// written in fragments: once a fragmented file's header is out, frames whose color tags change (as live
/// frames do) fail the next fragment (AVFoundation -11800, MovieHeaderMaker -16341).
final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    /// Called once, on a private queue, when the stream stops on its own (display gone, access revoked)
    /// or the file cannot be written. `stop()` still has to be called to finish the file.
    private let onInterrupt: (@Sendable (Error) -> Void)?

    private let queue = DispatchQueue(label: "SmartIME.ScreenRecorder", qos: .userInitiated)
    private let request: ScreenRecordingRequest
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private var stream: SCStream?

    // Only touched on `queue`.
    private var sessionStarted = false
    private var finished = false
    private var interrupted = false
    private var lastTime = CMTime.invalid
    private var lastArrival = CMTime.invalid
    private(set) var frameCount = 0

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
        guard writer.canAdd(input) else {
            throw ScreenRecorderError.cannotWrite("the video settings were refused")
        }
        writer.add(input)
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
        configuration.capturesAudio = false

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
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
    /// still screen at the end is kept.
    func stop() async throws {
        if let stream {
            self.stream = nil
            try? await stream.stopCapture()
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                self.finish(continuation)
            }
        }
    }

    private func finish(_ continuation: CheckedContinuation<Void, Error>) {
        guard !finished else {
            continuation.resume()
            return
        }
        finished = true
        guard sessionStarted, writer.status == .writing else {
            let error = writer.error
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: request.url)
            continuation.resume(throwing: error.map { ScreenRecorderError.cannotWrite(Self.describe($0)) } ?? ScreenRecorderError.noFrames)
            return
        }
        input.markAsFinished()
        // Frame times and the host clock may not share a base, so the end is the last frame's time
        // plus how long ago it arrived.
        let sinceLast = CMTimeSubtract(Self.hostTime(), lastArrival)
        writer.endSession(atSourceTime: CMTimeAdd(lastTime, CMTimeMaximum(sinceLast, .zero)))
        writer.finishWriting {
            if self.writer.status == .completed {
                continuation.resume()
            } else {
                continuation.resume(throwing: ScreenRecorderError.cannotWrite(Self.describe(self.writer.error)))
            }
        }
    }

    // MARK: SCStreamOutput, SCStreamDelegate

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        if type == .screen {
            append(sampleBuffer)
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

    private static func videoSettings(for request: ScreenRecordingRequest) -> [String: Any] {
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
            ],
        ]
    }
}
