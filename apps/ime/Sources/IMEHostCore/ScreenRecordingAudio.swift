import AppKit
import AVFoundation

/// Sound for screen recordings: system audio (apps, such as the other people in a meeting) and the
/// microphone, mixed into one stereo 48 kHz track. One track, because most players and chat previews
/// play only the first audio track of a file.
enum ScreenRecordingAudio {
    enum Source: CaseIterable {
        case system
        case microphone
    }

    enum MicrophoneAccess {
        case granted
        case denied
        case notDetermined
        /// ScreenCaptureKit records the microphone from macOS 15.
        case unsupported
    }

    static let sampleRate = 48_000.0
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false)!

    static var microphoneSupported: Bool {
        if #available(macOS 15.0, *) {
            return true
        }
        return false
    }

    static var microphoneAccess: MicrophoneAccess {
        guard microphoneSupported else {
            return .unsupported
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    /// Asks once (the system shows its prompt); later calls return the stored answer.
    static func requestMicrophoneAccess() async -> Bool {
        switch microphoneAccess {
        case .granted: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .unsupported: return false
        }
    }

    static func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    /// AAC at 128 kbit/s: plenty for speech and fine for music.
    static var writerSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000,
        ]
    }

    /// A copy of the PCM in a sample buffer from ScreenCaptureKit, in the buffer's own format.
    static func pcmBuffer(_ sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = sampleBuffer.formatDescription,
              description.mediaType == .audio,
              sampleBuffer.numSamples > 0 else {
            return nil
        }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let frames = AVAudioFrameCount(sampleBuffer.numSamples)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            return nil
        }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
        return status == noErr ? buffer : nil
    }

    /// A sample buffer for the writer holding a copy of `buffer`, starting at `time`.
    static func sampleBuffer(_ buffer: AVAudioPCMBuffer, at time: CMTime) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(buffer.format.sampleRate)),
            presentationTimeStamp: time, decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreate(
            allocator: nil, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil,
            formatDescription: buffer.format.formatDescription, sampleCount: CMItemCount(buffer.frameLength),
            sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil,
            sampleBufferOut: &sample
        ) == noErr, let sample else {
            return nil
        }
        guard CMSampleBufferSetDataBufferFromAudioBufferList(
            sample, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, bufferList: buffer.audioBufferList
        ) == noErr else {
            return nil
        }
        return sample
    }
}

/// Turns one source's buffers into 48 kHz float samples for the mixer: left and right, a mono source
/// in both. The microphone comes in its device's format (often mono, 16 or 24 kHz on a headset), so
/// it is resampled; a new device mid-recording brings a new format and a new converter.
final class ScreenRecordingAudioConverter {
    private var converter: AVAudioConverter?
    private var output: AVAudioFormat?

    func convert(_ input: AVAudioPCMBuffer) -> (left: [Float], right: [Float])? {
        guard input.frameLength > 0 else {
            return nil
        }
        let channels = AVAudioChannelCount(min(input.format.channelCount, 2))
        let buffer: AVAudioPCMBuffer
        if input.format.commonFormat == .pcmFormatFloat32, !input.format.isInterleaved,
           input.format.sampleRate == ScreenRecordingAudio.sampleRate, input.format.channelCount <= 2 {
            buffer = input
        } else {
            guard let converted = resample(input, channels: channels) else {
                return nil
            }
            buffer = converted
        }
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else {
            return nil
        }
        let count = Int(buffer.frameLength)
        let left = Array(UnsafeBufferPointer(start: data[0], count: count))
        let right = buffer.format.channelCount > 1 ? Array(UnsafeBufferPointer(start: data[1], count: count)) : left
        return (left, right)
    }

    private func resample(_ input: AVAudioPCMBuffer, channels: AVAudioChannelCount) -> AVAudioPCMBuffer? {
        if converter?.inputFormat != input.format {
            guard let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: ScreenRecordingAudio.sampleRate, channels: channels, interleaved: false),
                  let converter = AVAudioConverter(from: input.format, to: output) else {
                return nil
            }
            converter.downmix = input.format.channelCount > 2
            self.converter = converter
            self.output = output
        }
        guard let converter, let output else {
            return nil
        }
        let ratio = ScreenRecordingAudio.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 64
        guard let result = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else {
            return nil
        }
        // The converter calls back on this thread, during `convert`.
        nonisolated(unsafe) var pending: AVAudioPCMBuffer? = input
        var error: NSError?
        let status = converter.convert(to: result, error: &error) { _, inputStatus in
            guard let buffer = pending else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            pending = nil
            inputStatus.pointee = .haveData
            return buffer
        }
        return status == .error ? nil : result
    }
}

/// Places each source's samples on one timeline by their timestamps and hands out the sum.
///
/// Frame 0 is `origin` (the video's first frame); earlier samples are dropped. A source's next buffer
/// is placed right after its previous one when its timestamp is within 50 ms of that, so clock jitter
/// leaves no clicks; a larger jump leaves silence, or drops what overlaps. Mixed audio is handed out up
/// to where every source has delivered, but never more than `latency` behind the furthest source, so a
/// source that goes quiet (no buffers at all) does not hold the others back.
final class ScreenRecordingAudioMixer {
    let origin: CMTime
    let sources: [ScreenRecordingAudio.Source]
    /// Frames.
    let latency: Int
    let tolerance = Int(ScreenRecordingAudio.sampleRate * 0.05)
    /// Frames handed out so far; the next chunk starts here.
    private(set) var emitted = 0
    private var tracks: [ScreenRecordingAudio.Source: Track] = [:]

    private struct Track {
        /// Frame index of `left[0]`.
        var start: Int
        var left: [Float] = []
        var right: [Float] = []
        var seen = false
        var next: Int { start + left.count }
    }

    init(origin: CMTime, sources: [ScreenRecordingAudio.Source], latency: TimeInterval = 0.25) {
        self.origin = origin
        self.sources = sources
        self.latency = sources.count > 1 ? Int(latency * ScreenRecordingAudio.sampleRate) : 0
    }

    func add(left: [Float], right: [Float], at time: CMTime, from source: ScreenRecordingAudio.Source) {
        guard sources.contains(source), !left.isEmpty, left.count == right.count, time.isNumeric else {
            return
        }
        var track = tracks[source] ?? Track(start: emitted)
        var position = Int((CMTimeSubtract(time, origin).seconds * ScreenRecordingAudio.sampleRate).rounded())
        if track.seen, abs(position - track.next) <= tolerance {
            position = track.next
        }
        track.seen = true
        var skip = 0
        if position < track.next {
            skip = track.next - position
            position = track.next
        }
        if skip < left.count {
            if position > track.next {
                let gap = position - track.next
                track.left.append(contentsOf: repeatElement(0, count: gap))
                track.right.append(contentsOf: repeatElement(0, count: gap))
            }
            track.left.append(contentsOf: left[skip...])
            track.right.append(contentsOf: right[skip...])
        }
        tracks[source] = track
    }

    /// The next mixed chunk and its start time, or nil when nothing is ready. `flush` hands out
    /// everything received, for the end of the recording.
    func take(flush: Bool = false) -> (buffer: AVAudioPCMBuffer, time: CMTime)? {
        let ends = sources.map { tracks[$0]?.next ?? emitted }
        guard let latest = ends.max(), let earliest = ends.min() else {
            return nil
        }
        let end = flush ? latest : max(earliest, latest - latency)
        let count = end - emitted
        guard count > 0, let buffer = AVAudioPCMBuffer(pcmFormat: ScreenRecordingAudio.format, frameCapacity: AVAudioFrameCount(count)),
              let channels = buffer.floatChannelData else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(count)
        let left = channels[0]
        let right = channels[1]
        left.initialize(repeating: 0, count: count)
        right.initialize(repeating: 0, count: count)
        for source in sources {
            guard var track = tracks[source] else {
                continue
            }
            let from = max(track.start, emitted)
            let to = min(track.next, end)
            if from < to {
                for frame in from..<to {
                    left[frame - emitted] += track.left[frame - track.start]
                    right[frame - emitted] += track.right[frame - track.start]
                }
            }
            let used = min(max(end - track.start, 0), track.left.count)
            track.left.removeFirst(used)
            track.right.removeFirst(used)
            track.start = max(track.start + used, end)
            tracks[source] = track
        }
        for frame in 0..<count {
            left[frame] = min(max(left[frame], -1), 1)
            right[frame] = min(max(right[frame], -1), 1)
        }
        let time = CMTimeAdd(origin, CMTime(value: CMTimeValue(emitted), timescale: CMTimeScale(ScreenRecordingAudio.sampleRate)))
        emitted = end
        return (buffer, time)
    }
}
