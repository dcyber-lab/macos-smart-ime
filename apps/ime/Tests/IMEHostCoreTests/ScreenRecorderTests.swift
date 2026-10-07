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
