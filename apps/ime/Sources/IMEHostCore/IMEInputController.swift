import AppKit
@preconcurrency import InputMethodKit
import RimeBridge
import SharedModels

public final class IMEInputController: IMKInputController {
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
        static let downArrow: UInt16 = 125
        static let upArrow: UInt16 = 126
    }

    private enum CandidatePanel {
        static let selectionKeys: [NSNumber] = [18, 19, 20, 21, 23, 22, 26, 28, 25].map(NSNumber.init(value:))
    }

    private let sessionStore = IMEHostSessionStore()
    private let chineseEngine: ChineseInputEngine?
    private var candidateWindow: IMKCandidates?
    private var isSyncingCandidateSelection = false

    public override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        do {
            chineseEngine = try RimeBridgeEngine(
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
        } catch {
            chineseEngine = nil
        }

        super.init(server: server, delegate: delegate, client: inputClient)

    }

    public override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    public override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown else {
            return false
        }

        guard let chineseEngine else {
            return false
        }

        if event.keyCode == KeyCode.escape, sessionStore.hasActiveComposition {
            resetChineseSession(resetEngine: true)
            return true
        }

        if sessionStore.hasActiveComposition {
            if let candidateIndex = candidateIndex(for: event.keyCode) {
                return apply(chineseEngine.selectCandidate(at: candidateIndex), sender: sender)
            }

            if let highlightedIndex = highlightedCandidateIndexDelta(for: event.keyCode) {
                let targetIndex = nextHighlightedCandidateIndex(offset: highlightedIndex)
                guard let targetIndex else {
                    return true
                }
                return apply(chineseEngine.highlightCandidate(at: targetIndex), sender: sender)
            }
        }

        let update = chineseEngine.process(
            InputKeyEvent(
                keyCode: event.keyCode,
                characters: event.characters ?? "",
                charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                modifierFlags: event.modifierFlags.rawValue
            )
        )

        guard update.handled || update.commitText != nil || !update.state.compositionText.isEmpty else {
            return false
        }

        sessionStore.apply(update)
        if let committedText = update.commitText, !committedText.isEmpty {
            commit(committedText, using: sender)
            sessionStore.reset(committedText: committedText)
        }
        syncPresentation()
        return true
    }

    public override func composedString(_ sender: Any!) -> Any! {
        let composition = sessionStore.state.compositionText
        return composition.isEmpty ? nil : composition
    }

    public override func originalString(_ sender: Any!) -> NSAttributedString! {
        NSAttributedString(string: sessionStore.state.rawInput)
    }

    public override func candidates(_ sender: Any!) -> [Any]! {
        sessionStore.state.candidates.map(\.text)
    }

    public override func commitComposition(_ sender: Any!) {
        commit(sessionStore.state.compositionText, using: sender)
        resetChineseSession(resetEngine: true)
    }

    public override func deactivateServer(_ sender: Any!) {
        super.deactivateServer(sender)
        resetChineseSession(resetEngine: true)
    }

    public override func inputControllerWillClose() {
        super.inputControllerWillClose()
        resetChineseSession(resetEngine: true)
    }

    public override func candidateSelected(_ candidateString: NSAttributedString!) {
        let selectedText = candidateString?.string ?? ""
        guard !selectedText.isEmpty else {
            resetChineseSession(resetEngine: true)
            return
        }

        commit(selectedText, using: client())
        chineseEngine?.reset()
        sessionStore.reset(committedText: selectedText)
        syncPresentation()
    }

    public override func candidateSelectionChanged(_ candidateString: NSAttributedString!) {
        if isSyncingCandidateSelection {
            return
        }

        guard let candidateString else {
            return
        }

        let candidates = sessionStore.state.candidates.map(\.text)
        guard let index = candidates.firstIndex(of: candidateString.string) else {
            return
        }

        let update = chineseEngine?.highlightCandidate(at: index)
        if let update {
            _ = apply(update, sender: client())
        }
    }

    private func commit(_ committedText: String, using sender: Any?) {
        guard !committedText.isEmpty else {
            return
        }

        if let client = (sender as AnyObject?) as? NSTextInputClient {
            client.insertText(committedText, replacementRange: NSRange(location: NSNotFound, length: 0))
        } else if let client = self.client() as? NSTextInputClient {
            client.insertText(committedText, replacementRange: NSRange(location: NSNotFound, length: 0))
        }
    }

    private func resetChineseSession(resetEngine: Bool) {
        if resetEngine {
            chineseEngine?.reset()
        }
        sessionStore.reset()
        syncPresentation()
    }

    @discardableResult
    private func apply(_ update: InputSessionUpdate, sender: Any?) -> Bool {
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
        if candidateWindow == nil {
            let candidateWindow = IMKCandidates(server: server(), panelType: kIMKSingleColumnScrollingCandidatePanel)
            candidateWindow?.setSelectionKeys(CandidatePanel.selectionKeys)
            candidateWindow?.setAttributes([IMKCandidatesSendServerKeyEventFirst: NSNumber(value: true)])
            candidateWindow?.setDismissesAutomatically(true)
            self.candidateWindow = candidateWindow
        }

        guard let candidateWindow else {
            return
        }

        let candidates = sessionStore.state.candidates.map(\.text)
        let shouldShowCandidates = !sessionStore.state.compositionText.isEmpty && !candidates.isEmpty

        if shouldShowCandidates {
            candidateWindow.setCandidateData(candidates)
            if let selectedCandidateIndex = sessionStore.state.selectedCandidateIndex,
               candidates.indices.contains(selectedCandidateIndex)
            {
                let selectedCandidate = candidates[selectedCandidateIndex]
                let identifier = candidateWindow.candidateStringIdentifier(selectedCandidate)
                if identifier != NSNotFound {
                    isSyncingCandidateSelection = true
                    _ = candidateWindow.selectCandidate(withIdentifier: identifier)
                    isSyncingCandidateSelection = false
                }
            } else {
                isSyncingCandidateSelection = true
                candidateWindow.clearSelection()
                isSyncingCandidateSelection = false
            }
            if candidateWindow.isVisible() {
                candidateWindow.update()
            } else {
                candidateWindow.show(kIMKLocateCandidatesBelowHint)
            }
        } else {
            isSyncingCandidateSelection = true
            candidateWindow.clearSelection()
            isSyncingCandidateSelection = false
            candidateWindow.hide()
        }
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
