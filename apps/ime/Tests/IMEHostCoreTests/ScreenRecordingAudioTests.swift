import AVFoundation
import XCTest
@testable import IMEHostCore

final class ScreenRecordingAudioMixerTests: XCTestCase {
    private let origin = CMTime(value: 1_000 * 48_000, timescale: 48_000)

    func testOneSourceIsHandedOutAtOnce() throws {
        let mixer = ScreenRecordingAudioMixer(origin: origin, sources: [.system])
        mixer.add(left: Array(repeating: 0.5, count: 480), right: Array(repeating: -0.5, count: 480), at: origin, from: .system)
        let chunk = try XCTUnwrap(mixer.take())
        XCTAssertEqual(chunk.time, origin)
        XCTAssertEqual(Self.left(chunk.buffer), Array(repeating: 0.5, count: 480))
        XCTAssertEqual(Self.right(chunk.buffer), Array(repeating: -0.5, count: 480))
        XCTAssertNil(mixer.take())
    }

    /// The meeting (system) and the user's voice (microphone) add up where they overlap.
    func testTwoSourcesAreSummedOnOneTimeline() throws {
        let mixer = ScreenRecordingAudioMixer(origin: origin, sources: [.system, .microphone])
        mixer.add(left: Self.constant(0.5, 4_800), right: Self.constant(0.5, 4_800), at: origin, from: .system)
        mixer.add(left: Self.constant(0.25, 4_800), right: Self.constant(0.25, 4_800), at: time(2_400), from: .microphone)
        let first = try XCTUnwrap(mixer.take())
        XCTAssertEqual(first.time, origin)
        XCTAssertEqual(Self.left(first.buffer), Self.constant(0.5, 2_400) + Self.constant(0.75, 2_400))
        XCTAssertNil(mixer.take(), "waits for the system audio after 0.1 s")
        let rest = try XCTUnwrap(mixer.take(flush: true))
        XCTAssertEqual(rest.time, time(4_800))
        XCTAssertEqual(Self.left(rest.buffer), Self.constant(0.25, 2_400))
    }

    /// A source that sends nothing (no microphone buffers yet) holds the other back by the latency only.
    func testASilentSourceDelaysByTheLatencyOnly() throws {
        let mixer = ScreenRecordingAudioMixer(origin: origin, sources: [.system, .microphone], latency: 0.25)
        mixer.add(left: Self.constant(0.5, 48_000), right: Self.constant(0.5, 48_000), at: origin, from: .system)
        let chunk = try XCTUnwrap(mixer.take())
        XCTAssertEqual(Int(chunk.buffer.frameLength), 48_000 - 12_000)
        XCTAssertEqual(mixer.take(flush: true)?.buffer.frameLength, 12_000)
    }

    func testJitterIsAbsorbedAndGapsBecomeSilence() throws {
        let mixer = ScreenRecordingAudioMixer(origin: origin, sources: [.system])
        mixer.add(left: Self.constant(0.5, 480), right: Self.constant(0.5, 480), at: origin, from: .system)
        // 1 ms early: placed right after the first buffer.
        mixer.add(left: Self.constant(0.5, 480), right: Self.constant(0.5, 480), at: time(480 - 48), from: .system)
        // 0.1 s later than expected: silence in between.
        mixer.add(left: Self.constant(0.5, 480), right: Self.constant(0.5, 480), at: time(960 + 4_800), from: .system)
        let chunk = try XCTUnwrap(mixer.take())
        XCTAssertEqual(Self.left(chunk.buffer), Self.constant(0.5, 960) + Self.constant(0, 4_800) + Self.constant(0.5, 480))
    }

    func testSoundBeforeTheStartAndLateSoundAreDropped() throws {
        let mixer = ScreenRecordingAudioMixer(origin: origin, sources: [.system])
        mixer.add(left: Self.constant(0.5, 960), right: Self.constant(0.5, 960), at: time(-480), from: .system)
        let chunk = try XCTUnwrap(mixer.take())
        XCTAssertEqual(chunk.time, origin)
        XCTAssertEqual(chunk.buffer.frameLength, 480)
        // Already handed out: nothing new.
        mixer.add(left: Self.constant(0.5, 240), right: Self.constant(0.5, 240), at: time(-2_000_000), from: .system)
        XCTAssertNil(mixer.take(flush: true))
    }

    func testLoudSumsAreClipped() throws {
        let mixer = ScreenRecordingAudioMixer(origin: origin, sources: [.system, .microphone])
        mixer.add(left: Self.constant(0.8, 100), right: Self.constant(-0.8, 100), at: origin, from: .system)
        mixer.add(left: Self.constant(0.8, 100), right: Self.constant(-0.8, 100), at: origin, from: .microphone)
        let chunk = try XCTUnwrap(mixer.take())
        XCTAssertEqual(Self.left(chunk.buffer), Self.constant(1, 100))
        XCTAssertEqual(Self.right(chunk.buffer), Self.constant(-1, 100))
    }

    /// A headset microphone: mono at 24 kHz comes out at 48 kHz in both channels.
    func testMonoMicrophoneIsResampledIntoBothChannels() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false))
        let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2_400))
        input.frameLength = 2_400
        for frame in 0..<2_400 {
            input.floatChannelData![0][frame] = Float(sin(Double(frame) * 2 * .pi * 440 / 24_000) * 0.5)
        }
        let converter = ScreenRecordingAudioConverter()
        let first = try XCTUnwrap(converter.convert(input))
        let second = try XCTUnwrap(converter.convert(input))
        XCTAssertEqual(first.left, first.right)
        XCTAssertEqual(Double(first.left.count + second.left.count), 9_600, accuracy: 400)
        XCTAssertEqual(Double(second.left.map(abs).max() ?? 0), 0.5, accuracy: 0.05)
    }

    func testSampleBuffersRoundTrip() throws {
        let mixer = ScreenRecordingAudioMixer(origin: origin, sources: [.system])
        mixer.add(left: Self.constant(0.5, 480), right: Self.constant(0.25, 480), at: origin, from: .system)
        let chunk = try XCTUnwrap(mixer.take())
        let sample = try XCTUnwrap(ScreenRecordingAudio.sampleBuffer(chunk.buffer, at: chunk.time))
        XCTAssertTrue(CMSampleBufferDataIsReady(sample))
        XCTAssertEqual(sample.numSamples, 480)
        XCTAssertEqual(sample.presentationTimeStamp, origin)
        let back = try XCTUnwrap(ScreenRecordingAudio.pcmBuffer(sample))
        XCTAssertEqual(Self.right(back), Self.constant(0.25, 480))
    }

    private func time(_ frames: Int) -> CMTime {
        CMTimeAdd(origin, CMTime(value: CMTimeValue(frames), timescale: 48_000))
    }

    private static func constant(_ value: Float, _ count: Int) -> [Float] {
        Array(repeating: value, count: count)
    }

    private static func left(_ buffer: AVAudioPCMBuffer) -> [Float] {
        Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }

    private static func right(_ buffer: AVAudioPCMBuffer) -> [Float] {
        Array(UnsafeBufferPointer(start: buffer.floatChannelData![1], count: Int(buffer.frameLength)))
    }
}
