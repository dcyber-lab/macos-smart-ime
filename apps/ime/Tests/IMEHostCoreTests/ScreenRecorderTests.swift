import AVFoundation
import ScreenCaptureKit
import XCTest
@testable import IMEHostCore

/// Drives the writer half of `ScreenRecorder` with frames shaped like ScreenCaptureKit's; capturing the
/// screen itself needs Screen Recording access and is checked by hand.
@MainActor
final class ScreenRecorderTests: XCTestCase {
    private let url = FileManager.default.temporaryDirectory.appendingPathComponent("ScreenRecorderTests-\(UUID().uuidString).mp4")

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
        super.tearDown()
    }

    /// Live recordings stopped after a few seconds (AVFoundation -11800, MovieHeaderMaker -16341): with
    /// B-frames on, a fragmented writer failed at a fragment in about two of three 5-second runs.
    func testEncoderKeepsFramesInOrderForFragments() throws {
        let settings = ScreenRecorder.videoSettings(for: request(width: 320, height: 180))
        let compression = try XCTUnwrap(settings[AVVideoCompressionPropertiesKey] as? [String: Any])
        XCTAssertEqual(compression[AVVideoAllowFrameReorderingKey] as? Bool, false)
    }

    /// A live-paced stream whose color tags change after the first fragment completes, and the file
    /// plays before the stop, so a crash keeps what was recorded.
    func testLiveStreamPlaysWhileRecordingAndCompletes() async throws {
        let recorder = try ScreenRecorder(request: request(width: 320, height: 180))
        for index in 0..<150 {
            let time = CMClockGetTime(CMClockGetHostTimeClock())
            recorder.append(Self.frame(width: 320, height: 180, time: time, displayP3: index >= 75))
            try await Task.sleep(nanoseconds: 33_000_000)
        }
        let playsBeforeStop = await ScreenRecorder.isPlayable(url)
        XCTAssertTrue(playsBeforeStop, "fragments are written while recording")
        let ending = try await recorder.stop()
        XCTAssertEqual(ending, .complete)
        let tracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 320, height: 180))
        XCTAssertGreaterThan(recorder.frameCount, 75)
        let audioTracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .audio)
        XCTAssertTrue(audioTracks.isEmpty, "no sound unless asked for")
    }

    /// A meeting tone (system audio, 48 kHz stereo) and a voice tone (a headset microphone, 24 kHz mono)
    /// end up summed in one AAC track. The screen goes still halfway (no new frames, as with a shared
    /// slide), and the sound keeps going to the end.
    func testSoundIsMixedIntoOneAACTrack() async throws {
        var request = request(width: 320, height: 180)
        request.systemAudio = true
        request.microphone = true
        let recorder = try ScreenRecorder(request: request)
        let start = CMClockGetTime(CMClockGetHostTimeClock())
        recorder.append(Self.frame(width: 320, height: 180, time: start))
        for index in 0..<60 {
            if index > 0, index < 30 {
                recorder.append(Self.frame(width: 320, height: 180, time: CMClockGetTime(CMClockGetHostTimeClock())))
            }
            let time = CMTimeAdd(start, CMTime(value: CMTimeValue(index), timescale: 30))
            recorder.appendAudio(Self.tone(hertz: 440, rate: 48_000, channels: 2, frames: 1_600, offset: index * 1_600, time: time), from: .system)
            recorder.appendAudio(Self.tone(hertz: 300, rate: 24_000, channels: 1, frames: 800, offset: index * 800, time: time), from: .microphone)
            try await Task.sleep(nanoseconds: 33_000_000)
        }
        let ending = try await recorder.stop()
        XCTAssertEqual(ending, .complete)
        XCTAssertGreaterThan(recorder.audioFrameCount, 48_000 * 19 / 10)

        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(tracks.count, 1)
        let track = try XCTUnwrap(tracks.first)
        let formats = try await track.load(.formatDescriptions)
        XCTAssertEqual(formats.first?.mediaSubType, .mpeg4AAC)
        let range = try await track.load(.timeRange)
        XCTAssertEqual(range.duration.seconds, 2, accuracy: 0.2)
        // Each tone peaks at 0.25; only their sum gets above 0.3.
        let peak = try Self.peak(of: track, in: asset)
        XCTAssertGreaterThan(peak, 0.3)
        XCTAssertLessThan(peak, 0.6)
    }

    /// After a write error the file is kept only if it plays.
    func testUnreadableFileIsNotPlayable() async throws {
        try Data("not a movie".utf8).write(to: url)
        let playable = await ScreenRecorder.isPlayable(url)
        XCTAssertFalse(playable)
    }

    func testIdleFramesAreSkippedAndAStopWithoutFramesLeavesNoFile() async throws {
        let recorder = try ScreenRecorder(request: request(width: 320, height: 180))
        recorder.append(Self.frame(width: 320, height: 180, time: CMClockGetTime(CMClockGetHostTimeClock()), status: .idle))
        XCTAssertEqual(recorder.frameCount, 0)
        do {
            try await recorder.stop()
            XCTFail("stopping without frames should throw")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
    }

    /// A sine at a quarter of full scale, shaped like ScreenCaptureKit's audio (float, non-interleaved).
    private static func tone(hertz: Double, rate: Double, channels: AVAudioChannelCount, frames: Int, offset: Int, time: CMTime) -> CMSampleBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: channels, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for channel in 0..<Int(channels) {
            for frame in 0..<frames {
                buffer.floatChannelData![channel][frame] = Float(sin(Double(offset + frame) * 2 * .pi * hertz / rate) * 0.25)
            }
        }
        return ScreenRecordingAudio.sampleBuffer(buffer, at: time)!
    }

    /// The loudest sample of the decoded track.
    private static func peak(of track: AVAssetTrack, in asset: AVAsset) throws -> Float {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var peak: Float = 0
        while let sample = output.copyNextSampleBuffer() {
            guard let block = sample.dataBuffer, let data = try? block.dataBytes() else {
                continue
            }
            data.withUnsafeBytes { raw in
                for value in raw.bindMemory(to: Float.self) {
                    peak = max(peak, abs(value))
                }
            }
        }
        return peak
    }

    private func request(width: Int, height: Int) -> ScreenRecordingRequest {
        ScreenRecordingRequest(displayID: 0, sourceRect: .zero, width: width, height: height, frameRate: 30, excludedWindowIDs: [], url: url)
    }

    /// A gray 420v frame marked with ScreenCaptureKit's frame status.
    private static func frame(width: Int, height: Int, time: CMTime, status: SCFrameStatus = .complete, displayP3: Bool = false) -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixelBuffer)
        let buffer = pixelBuffer!
        if displayP3 {
            CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_P3_D65, .shouldPropagate)
            CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_sRGB, .shouldPropagate)
            CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddressOfPlane(buffer, 0), 120, CVPixelBufferGetBytesPerRowOfPlane(buffer, 0) * height)
        memset(CVPixelBufferGetBaseAddressOfPlane(buffer, 1), 128, CVPixelBufferGetBytesPerRowOfPlane(buffer, 1) * height / 2)
        CVPixelBufferUnlockBaseAddress(buffer, [])
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format)
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: buffer, formatDescription: format!, sampleTiming: &timing, sampleBufferOut: &sample)
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample!, createIfNecessary: true)! as NSArray
        (attachments[0] as! NSMutableDictionary)[SCStreamFrameInfo.status.rawValue] = NSNumber(value: status.rawValue)
        return sample!
    }
}
