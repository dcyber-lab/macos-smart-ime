import AppKit

/// A recording in progress: a red frame just outside the area, a small bar with the elapsed time and a
/// stop button, and the recorder writing the file. Both windows are left out of the video.
@MainActor
final class ScreenRecordingSession {
    struct Outcome {
        let url: URL
        let duration: TimeInterval
        let width: Int
        let height: Int
        /// Why the recording stopped on its own, if it did.
        let interruption: String?
    }

    let url: URL
    private let request: ScreenRecordingRequest
    private let frameWindow: ScreenRecordingFrameWindow
    private let controls: ScreenRecordingControls
    private let onFinish: @MainActor (Result<Outcome, Error>) -> Void
    private var recorder: ScreenRecorder?
    private var timer: Timer?
    private var startedAt = Date()
    private var interruption: String?
    private var stopping = false

    /// Shows the frame and the controls, then starts capturing `area` (global Cocoa coordinates, on one
    /// screen). Throws when the area is too small, its display is gone, or the file cannot be written.
    static func start(
        area: CGRect, frameRate: Int, url: URL, stopHint: String,
        onFinish: @escaping @MainActor (Result<Outcome, Error>) -> Void
    ) async throws -> ScreenRecordingSession {
        let center = CGPoint(x: area.midX, y: area.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let source = ScreenRecordingGeometry.source(of: area, screenFrame: screen.frame, scale: screen.backingScaleFactor) else {
            throw ScreenRecorderError.displayNotFound
        }
        let output = ScreenRecordingGeometry.outputSize(pixelWidth: source.pixelWidth, pixelHeight: source.pixelHeight)
        let recorded = CGRect(
            x: screen.frame.minX + source.rect.minX, y: screen.frame.maxY - source.rect.maxY,
            width: source.rect.width, height: source.rect.height
        )
        let frameWindow = ScreenRecordingFrameWindow(around: recorded)
        let controls = ScreenRecordingControls(stopHint: stopHint)
        controls.place(near: frameWindow.frame, on: screen.frame)
        frameWindow.orderFrontRegardless()
        controls.orderFrontRegardless()

        let request = ScreenRecordingRequest(
            displayID: number.uint32Value, sourceRect: source.rect, width: output.width, height: output.height,
            frameRate: frameRate,
            excludedWindowIDs: [CGWindowID(frameWindow.windowNumber), CGWindowID(controls.windowNumber)],
            url: url
        )
        let session = ScreenRecordingSession(request: request, frameWindow: frameWindow, controls: controls, onFinish: onFinish)
        do {
            let recorder = try await ScreenRecorder.start(request) { [weak session] error in
                Task { @MainActor in
                    session?.interrupt(error)
                }
            }
            session.begin(with: recorder)
        } catch {
            frameWindow.orderOut(nil)
            controls.orderOut(nil)
            throw error
        }
        return session
    }

    private init(
        request: ScreenRecordingRequest, frameWindow: ScreenRecordingFrameWindow, controls: ScreenRecordingControls,
        onFinish: @escaping @MainActor (Result<Outcome, Error>) -> Void
    ) {
        self.request = request
        url = request.url
        self.frameWindow = frameWindow
        self.controls = controls
        self.onFinish = onFinish
    }

    private func begin(with recorder: ScreenRecorder) {
        self.recorder = recorder
        startedAt = Date()
        controls.onStop = { [weak self] in self?.stop() }
        controls.setElapsed(0)
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else {
                    return
                }
                self.controls.setElapsed(Date().timeIntervalSince(self.startedAt))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // The stream may have stopped while it was starting.
        if interruption != nil {
            stop()
        }
    }

    private func interrupt(_ error: Error) {
        interruption = error.localizedDescription
        stop()
    }

    /// Hides the frame and the controls, then completes the file and reports the outcome.
    func stop() {
        guard !stopping, let recorder else {
            return
        }
        stopping = true
        timer?.invalidate()
        timer = nil
        frameWindow.orderOut(nil)
        controls.orderOut(nil)
        let duration = Date().timeIntervalSince(startedAt)
        Task { @MainActor in
            do {
                if case .cutShort(let reason) = try await recorder.stop(), self.interruption == nil {
                    self.interruption = reason
                }
                self.onFinish(.success(Outcome(
                    url: self.url, duration: duration, width: self.request.width, height: self.request.height,
                    interruption: self.interruption
                )))
            } catch {
                self.onFinish(.failure(error))
            }
        }
    }
}

/// A thin red line just outside the recorded area; clicks go through it.
final class ScreenRecordingFrameWindow: NSWindow {
    static let margin: CGFloat = 3

    init(around area: CGRect) {
        let frame = area.insetBy(dx: -Self.margin, dy: -Self.margin)
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        sharingType = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = FrameView(frame: CGRect(origin: .zero, size: frame.size))
        setFrame(frame, display: false)
    }

    private final class FrameView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            NSColor.systemRed.setStroke()
            let path = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
            path.lineWidth = 2
            path.stroke()
        }
    }
}

/// The elapsed time and a stop button, below the recorded area (above it, or inside it, when there is
/// no room). Drag it anywhere; it never takes focus from the app being recorded.
final class ScreenRecordingControls: NSPanel {
    var onStop: (() -> Void)?
    private let timeLabel = NSTextField(labelWithString: "0:00")

    init(stopHint: String) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        sharingType = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = CandidatePanel.roundedMask(radius: 8)

        let dot = NSImageView(image: NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium)) ?? NSImage())
        dot.contentTintColor = .systemRed
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let stop = NSButton(
            image: NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "Stop recording")?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .medium)) ?? NSImage(),
            target: nil, action: nil
        )
        stop.isBordered = false
        stop.contentTintColor = .systemRed
        stop.toolTip = "Stop recording \(stopHint)"
        stop.target = self
        stop.action = #selector(stopClicked)

        let row = NSStackView(views: [dot, timeLabel, stop])
        row.orientation = .horizontal
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        row.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            row.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            background.heightAnchor.constraint(equalToConstant: 32),
            timeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 52),
        ])
        contentView = background
        setContentSize(background.fittingSize)
    }

    func place(near frame: CGRect, on screenFrame: CGRect) {
        let origin = ScreenshotGeometry.toolbarOrigin(size: self.frame.size, selection: frame, bounds: screenFrame)
        setFrameOrigin(origin)
    }

    func setElapsed(_ seconds: TimeInterval) {
        timeLabel.stringValue = ScreenRecordingGeometry.elapsedText(seconds)
    }

    @objc private func stopClicked() {
        onStop?()
    }
}
