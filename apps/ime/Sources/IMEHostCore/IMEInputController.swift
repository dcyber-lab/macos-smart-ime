import AppKit
@preconcurrency import InputMethodKit
import RimeBridge
import EnglishEngine
import SharedModels

// Confined to the main thread: InputMethodKit creates and calls input controllers only there.
public final class IMEInputController: IMKInputController, @unchecked Sendable {
    private enum KeyCode {
        static let one: UInt16 = 18
        static let two: UInt16 = 19
        static let three: UInt16 = 20
        static let four: UInt16 = 21
        static let five: UInt16 = 23
        static let six: UInt16 = 22
        static let seven: UInt16 = 26
        static let eight: UInt16 = 28
        static let nine: UInt16 = 25
        static let escape: UInt16 = 53
        static let t: UInt16 = 17
        static let downArrow: UInt16 = 125
        static let upArrow: UInt16 = 126
    }

    private let sessionStore = IMEHostSessionStore()
    private let chineseEngine: ChineseInputEngine?
    private let englishEngine: EnglishInputEngine?
    private var shiftToggle = ShiftToggleDetector()
    /// Where the selection-translation popup is anchored (first character of the selection).
    private var translationAnchor = NSRect.zero
    private lazy var selectionTranslation = MainActor.assumeIsolated {
        SelectionTranslationController(translator: AppleSelectionTranslator()) { [weak self] state in
            TranslationPopup.shared.show(state, caretRect: self?.translationAnchor ?? .zero)
        }
    }

    private var activeEngine: (any ChineseInputEngine)? {
        switch sessionStore.state.mode {
        case .chinese:
            return chineseEngine
        case .english:
            // EnglishInputEngine and ChineseInputEngine share the same method signatures we use here.
            // We can cast or use a shared protocol if we had one, but for now we know both respond to these.
            // To satisfy Swift's type system without a shared protocol, we can just return the object.
            // Actually, let's just use the specific engines in handle.
            return nil 
        case .mixed:
            return nil
        }
    }

    public override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        do {
            let rimeEngine = try RimeBridgeEngine(
                configuration: RimeBridgeConfiguration(
                    sharedDataDirectory: IMEHostConfiguration.rimeSharedDataDirectory(),
                    userDataDirectory: IMEHostConfiguration.rimeUserDataDirectory(),
                    prebuiltDataDirectory: IMEHostConfiguration.rimeBuildDirectory(),
                    stagingDirectory: IMEHostConfiguration.rimeBuildDirectory(),
                    appName: "rime.smartime",
                    distributionName: "SmartIME Host",
                    distributionCodeName: "smart-ime",
                    distributionVersion: "0.1.0",
                    defaultSchemaID: IMEHostConfiguration.defaultSchemaID
                )
            )
            chineseEngine = EnglishAugmentedChineseEngine(base: rimeEngine)
        } catch {
            chineseEngine = nil
        }

        englishEngine = BasicEnglishEngine()

        super.init(server: server, delegate: delegate, client: inputClient)
        NSLog("SmartIME: IMEInputController init – chineseEngine=%@, englishEngine=%@, bundle=%@",
              chineseEngine == nil ? "nil" : "ok",
              englishEngine == nil ? "nil" : "ok",
              Bundle.main.bundlePath)
    }

    public override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue | NSEvent.EventTypeMask.flagsChanged.rawValue)
    }

    public override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event else {
            return false
        }

        if event.type == .flagsChanged {
            guard shiftToggle.flagsChanged(event.modifierFlags) else {
                return false
            }
            toggleInputMode()
            return true
        }

        guard event.type == .keyDown else {
            return false
        }
        shiftToggle.keyDown()

        if let handled = handleSelectionTranslationKey(event) {
            return handled
        }

        if event.keyCode == KeyCode.escape, sessionStore.hasActiveComposition {
            resetSession(resetEngine: true)
            return true
        }

        // Selection by number keys or arrows
        if sessionStore.hasActiveComposition {
            if let candidateIndex = candidateIndex(for: event.keyCode) {
                if sessionStore.state.mode == .chinese {
                    return apply(chineseEngine?.selectCandidate(at: candidateIndex), sender: sender)
                } else if sessionStore.state.mode == .english {
                    return apply(englishEngine?.selectCandidate(at: candidateIndex), sender: sender)
                }
            }

            if let highlightedIndex = highlightedCandidateIndexDelta(for: event.keyCode) {
                let targetIndex = nextHighlightedCandidateIndex(offset: highlightedIndex)
                if let targetIndex {
                    if sessionStore.state.mode == .chinese {
                        return apply(chineseEngine?.highlightCandidate(at: targetIndex), sender: sender)
                    } else if sessionStore.state.mode == .english {
                        return apply(englishEngine?.highlightCandidate(at: targetIndex), sender: sender)
                    }
                }
                return true
            }
        }

        let keyEvent = InputKeyEvent(
            keyCode: event.keyCode,
            characters: event.characters ?? "",
            charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
            modifierFlags: event.modifierFlags.rawValue
        )

        let update: InputSessionUpdate?
        if sessionStore.state.mode == .chinese {
            update = chineseEngine?.process(keyEvent)
        } else {
            update = englishEngine?.process(keyEvent)
        }

        guard let update else {
            return false
        }

        guard update.handled || update.commitText != nil || !update.state.compositionText.isEmpty else {
            return false
        }

        return apply(update, sender: sender)
    }

    private func toggleInputMode() {
        let newMode: InputMode = (sessionStore.state.mode == .chinese) ? .english : .chinese
        NSLog("SmartIME: toggling mode from %@ to %@", sessionStore.state.mode.rawValue, newMode.rawValue)
        
        // Reset current session before switching
        resetSession(resetEngine: true)
        sessionStore.setMode(newMode)
        syncPresentation()
    }

    public override func composedString(_ sender: Any!) -> Any! {
        // An empty string (not nil) makes updateComposition() clear the client's marked text, e.g. on Escape.
        sessionStore.state.compositionText
    }

    public override func originalString(_ sender: Any!) -> NSAttributedString! {
        NSAttributedString(string: sessionStore.state.rawInput)
    }

    public override func commitComposition(_ sender: Any!) {
        commit(sessionStore.state.compositionText, using: sender)
        chineseEngine?.reset()
        englishEngine?.reset()
        sessionStore.reset()
        withCandidatePanel { $0.hide() }
    }

    public override func deactivateServer(_ sender: Any!) {
        tearDownSession()
        super.deactivateServer(sender)
    }

    public override func inputControllerWillClose() {
        tearDownSession()
        super.inputControllerWillClose()
    }

    private func commit(_ committedText: String, using sender: Any?) {
        guard !committedText.isEmpty else {
            return
        }

        // InputMethodKit hands controllers IMKTextInput proxies; they never conform to NSTextInputClient.
        let target: IMKTextInput? = (sender as? IMKTextInput) ?? client()
        target?.insertText(committedText, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    private func resetSession(resetEngine: Bool) {
        if resetEngine {
            chineseEngine?.reset()
            englishEngine?.reset()
        }
        sessionStore.reset()
        syncPresentation()
    }

    private func tearDownSession() {
        chineseEngine?.reset()
        englishEngine?.reset()
        sessionStore.reset()
        withCandidatePanel { $0.hide() }
        MainActor.assumeIsolated { selectionTranslation.dismiss() }
    }

    // MARK: Selection translation (POC)

    /// Returns nil when the key is not part of the selection-translation flow and should be handled normally.
    private func handleSelectionTranslationKey(_ event: NSEvent) -> Bool? {
        let keyCode = event.keyCode
        let outcome = MainActor.assumeIsolated {
            selectionTranslation.isActive ? selectionTranslation.handleKey(keyCode) : nil
        }
        switch outcome {
        case .replace(let translation, let range)?:
            client()?.insertText(translation, replacementRange: range)
            return true
        case .dismissed(consumed: true)?:
            return true
        case .dismissed(consumed: false)?, nil:
            break
        }

        let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        guard keyCode == KeyCode.t, modifiers == [.control, .option], !sessionStore.hasActiveComposition else {
            return nil
        }
        startSelectionTranslation()
        return true
    }

    private func startSelectionTranslation() {
        let client = self.client()
        let range = client?.selectedRange() ?? NSRange(location: NSNotFound, length: 0)
        var selectedText: String?
        var anchor = NSRect.zero
        if let client, range.location != NSNotFound {
            selectedText = range.length > 0 ? client.attributedSubstring(from: range)?.string : ""
            _ = client.attributes(forCharacterIndex: range.location, lineHeightRectangle: &anchor)
        }
        translationAnchor = anchor
        let text = selectedText
        MainActor.assumeIsolated {
            selectionTranslation.start(selectedText: text, range: range)
        }
    }

    @discardableResult
    private func apply(_ update: InputSessionUpdate?, sender: Any?) -> Bool {
        guard let update else { return false }
        sessionStore.apply(update)
        if let committedText = update.commitText, !committedText.isEmpty {
            commit(committedText, using: sender)
            sessionStore.reset(committedText: committedText)
        }
        syncPresentation()
        return update.handled || update.commitText != nil || sessionStore.hasActiveComposition
    }

    private func syncPresentation() {
        updateComposition()
        syncCandidateWindow()
    }

    private func syncCandidateWindow() {
        let state = sessionStore.state
        guard !state.compositionText.isEmpty, !state.candidates.isEmpty else {
            withCandidatePanel { $0.hide() }
            return
        }

        let caretRect = caretRect()
        withCandidatePanel { panel in
            panel.show(state: state, caretRect: caretRect) { [weak self] index in
                self?.selectCandidateFromPanel(at: index)
            }
        }
    }

    /// InputMethodKit always calls input controllers on the main thread.
    private func withCandidatePanel(_ body: @MainActor (CandidatePanel) -> Void) {
        MainActor.assumeIsolated {
            body(CandidatePanel.shared)
        }
    }

    private func caretRect() -> NSRect {
        var rect = NSRect.zero
        _ = client()?.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        return rect
    }

    private func selectCandidateFromPanel(at index: Int) {
        let update: InputSessionUpdate?
        if sessionStore.state.mode == .chinese {
            update = chineseEngine?.selectCandidate(at: index)
        } else {
            update = englishEngine?.selectCandidate(at: index)
        }
        apply(update, sender: client())
    }

    private func candidateIndex(for keyCode: UInt16) -> Int? {
        switch keyCode {
        case KeyCode.one:
            return 0
        case KeyCode.two:
            return 1
        case KeyCode.three:
            return 2
        case KeyCode.four:
            return 3
        case KeyCode.five:
            return 4
        case KeyCode.six:
            return 5
        case KeyCode.seven:
            return 6
        case KeyCode.eight:
            return 7
        case KeyCode.nine:
            return 8
        default:
            return nil
        }
    }

    private func highlightedCandidateIndexDelta(for keyCode: UInt16) -> Int? {
        switch keyCode {
        case KeyCode.upArrow:
            return -1
        case KeyCode.downArrow:
            return 1
        default:
            return nil
        }
    }

    private func nextHighlightedCandidateIndex(offset: Int) -> Int? {
        let candidates = sessionStore.state.candidates
        guard !candidates.isEmpty else {
            return nil
        }

        let currentIndex = sessionStore.state.selectedCandidateIndex ?? 0
        let targetIndex = min(max(currentIndex + offset, 0), candidates.count - 1)
        return targetIndex
    }
}
