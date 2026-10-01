import AppKit
import Carbon.HIToolbox
@preconcurrency import InputMethodKit
import RimeBridge
import EnglishEngine
import SharedModels
import UserData

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
        static let downArrow: UInt16 = 125
        static let upArrow: UInt16 = 126
    }

    /// Shared by every input controller in the process so picks in one app count everywhere.
    private static let candidateHistory = CandidateHistory(fileURL: IMEHostConfiguration.candidateHistoryURL())
    private static let translationMisses = TranslationMisses(
        fileURL: IMEHostConfiguration.translationMissesURL(),
        isEnabled: { TranslationLearningSettings().isEnabled }
    )
    private static let userTranslations = UserTranslations(fileURL: IMEHostConfiguration.userTranslationsURL())
    @MainActor private static let translationLearner = TranslationLearner(
        misses: translationMisses,
        userTranslations: userTranslations
    )
    /// Intelligence hub: what is learned from committed text (see `docs/intelligence-hub.md`).
    @MainActor private static let intelligence = IntelligenceRecorder(
        settings: IntelligenceSettings(),
        memory: InputMemory(fileURL: IMEHostConfiguration.inputMemoryURL()),
        journal: InputJournal(directoryURL: IMEHostConfiguration.inputJournalDirectoryURL())
    )
    @MainActor private static var lastJournalPrune = Date.distantPast
    private static let returnKeys: Set<UInt16> = [36, 76]

    private let sessionStore = IMEHostSessionStore()
    private let commitEffectSettings = CommitEffectSettings()
    /// The client app, read once per activation so commits never wait on a round trip to it.
    private var clientBundleIdentifier: String?
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

    public override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        do {
            let rimeEngine = try RimeBridgeEngine(
                configuration: RimeBridgeConfiguration(
                    sharedDataDirectory: IMEHostConfiguration.rimeSharedDataDirectory(),
                    userDataDirectory: IMEHostConfiguration.rimeUserDataDirectory(),
                    prebuiltDataDirectory: IMEHostConfiguration.rimePrebuiltDataDirectory(),
                    stagingDirectory: IMEHostConfiguration.rimeBuildDirectory(),
                    appName: "rime.smartime",
                    distributionName: "SmartIME Host",
                    distributionCodeName: "smart-ime",
                    distributionVersion: "0.1.0",
                    defaultSchemaID: IMEHostConfiguration.defaultSchemaID
                )
            )
            chineseEngine = EnglishAugmentedChineseEngine(
                base: rimeEngine,
                userTranslations: Self.userTranslations,
                history: Self.candidateHistory,
                misses: Self.translationMisses
            )
        } catch {
            chineseEngine = nil
        }

        englishEngine = BasicEnglishEngine(history: Self.candidateHistory)

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

        if Self.returnKeys.contains(event.keyCode), !sessionStore.hasActiveComposition {
            MainActor.assumeIsolated { Self.intelligence.endSentence() }
        }

        if let handled = handleSelectionTranslationKey(event) {
            return handled
        }

        if event.keyCode == KeyCode.escape, sessionStore.hasActiveComposition {
            resetSession(resetEngine: true)
            return true
        }

        // Selection by number keys or arrows
        if sessionStore.hasActiveComposition {
            if let candidateIndex = Self.candidateIndex(forKeyCode: event.keyCode, modifierFlags: event.modifierFlags) {
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

    public override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        // Picks up hand edits of the user translation file, and learns missing translations once a day.
        Self.userTranslations.reloadIfChanged()
        clientBundleIdentifier = ((sender as? IMKTextInput) ?? client())?.bundleIdentifier()
        MainActor.assumeIsolated {
            Self.translationLearner.runIfDue()
            if Date().timeIntervalSince(Self.lastJournalPrune) > 24 * 60 * 60 {
                Self.lastJournalPrune = Date()
                Self.intelligence.journal.prune(keepingDays: Self.intelligence.settings.retentionDays)
            }
        }
    }

    public override func deactivateServer(_ sender: Any!) {
        MainActor.assumeIsolated { Self.intelligence.endSentence() }
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

    // MARK: Selection translation

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

        // Read on every key so `defaults write` changes apply without restarting the input method.
        let settings = SelectionTranslationSettings()
        guard settings.isEnabled,
              settings.hotkey.matches(keyCode: keyCode, modifierFlags: event.modifierFlags),
              !sessionStore.hasActiveComposition else {
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
            playCommitEffect(for: committedText)
            let app = clientBundleIdentifier, secureInput = IsSecureEventInputEnabled()
            MainActor.assumeIsolated { Self.intelligence.commit(committedText, app: app, secureInput: secureInput) }
            sessionStore.reset(committedText: committedText)
        }
        syncPresentation()
        return update.handled || update.commitText != nil || sessionStore.hasActiveComposition
    }

    /// Runs after the text is inserted; the effect is visual only and never delays input.
    private func playCommitEffect(for committedText: String) {
        var generator = SystemRandomNumberGenerator()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard let skin = commitEffectSettings.resolve(reduceMotion: reduceMotion, using: &generator) else {
            return
        }
        withCandidatePanel { $0.playCommitEffect(for: committedText, style: skin.style, palette: skin.palette) }
    }

    // MARK: Input menu

    public override func menu() -> NSMenu! {
        let menu = NSMenu()
        menu.autoenablesItems = false
        CommitEffectMenu.items(
            motion: commitEffectSettings.motion,
            palette: commitEffectSettings.palette,
            motionAction: #selector(selectCommitEffectMotion(_:)),
            paletteAction: #selector(selectCommitEffectPalette(_:))
        ).forEach(menu.addItem)
        menu.addItem(.separator())
        let currentApp = clientBundleIdentifier.map { (id: $0, name: AppNames.displayName(for: $0)) }
        IntelligenceMenu.items(settings: IntelligenceSettings(), currentApp: currentApp, action: #selector(intelligenceMenuCommand(_:)))
            .forEach(menu.addItem)
        return menu
    }

    @objc func intelligenceMenuCommand(_ sender: Any?) {
        guard let command = IntelligenceMenu.command(from: sender) else {
            NSLog("SmartIME: unrecognized intelligence menu item: %@", String(describing: sender))
            return
        }
        let app = clientBundleIdentifier
        MainActor.assumeIsolated {
            let settings = Self.intelligence.settings
            switch command {
            case .learning:
                settings.isLearningEnabled.toggle()
                if !settings.isLearningEnabled {
                    Self.intelligence.endSentence()
                }
            case .journal:
                settings.isJournalEnabled.toggle()
            case .excludeApp:
                if let app {
                    Self.intelligence.endSentence()
                    settings.toggleExcluded(app)
                }
            case .view:
                Self.openLearningPage()
            case .clear:
                Self.confirmAndClearLearning()
            }
            NSLog("SmartIME: intelligence menu %@ (learning %@, journal %@)", String(describing: command),
                  settings.isLearningEnabled ? "on" : "off", settings.isJournalEnabled ? "on" : "off")
        }
    }

    @MainActor private static func openLearningPage() {
        let settings = intelligence.settings
        let html = LearningPage.html(LearningPage.Input(
            isLearningEnabled: settings.isLearningEnabled,
            isJournalEnabled: settings.isJournalEnabled,
            retentionDays: settings.retentionDays,
            excludedApps: (PrivacyFilter.defaultExcludedApps.union(settings.excludedApps)).map(AppNames.displayName(for:)).sorted(),
            summary: intelligence.memory.summary(),
            entries: intelligence.journal.entries(days: settings.retentionDays),
            appName: AppNames.displayName(for:),
            generatedAt: Date()
        ))
        let url = IMEHostConfiguration.learningPageURL()
        PrivateFiles.write(Data(html.utf8), to: url)
        NSWorkspace.shared.open(url)
    }

    @MainActor private static func confirmAndClearLearning() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "清除学习记录？"
        alert.informativeText = "将删除智能中心的统计和输入原文、候选习惯、翻译学习记录，无法恢复。拼音的用户词库不受影响。"
        alert.addButton(withTitle: "清除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        intelligence.clear()
        candidateHistory.clear()
        translationMisses.clear()
        try? FileManager.default.removeItem(at: IMEHostConfiguration.learningPageURL())
        NSLog("SmartIME: learning records cleared")
    }

    /// Input menu choices arrive here first; the log shows whether the system delivered them.
    public override func doCommand(by aSelector: Selector!, command infoDictionary: [AnyHashable: Any]!) {
        NSLog("SmartIME: menu command %@", aSelector.map(NSStringFromSelector) ?? "nil")
        super.doCommand(by: aSelector, command: infoDictionary)
    }

    @objc func selectCommitEffectMotion(_ sender: Any?) {
        guard let choice = CommitEffectMenu.motionChoice(from: sender) else {
            NSLog("SmartIME: unrecognized commit effect menu item: %@", String(describing: sender))
            return
        }
        commitEffectSettings.motion = choice
        NSLog("SmartIME: commit effect motion set to %@", choice.rawValue)
        previewCommitEffect()
    }

    @objc func selectCommitEffectPalette(_ sender: Any?) {
        guard let choice = CommitEffectMenu.paletteChoice(from: sender) else {
            NSLog("SmartIME: unrecognized commit effect menu item: %@", String(describing: sender))
            return
        }
        commitEffectSettings.palette = choice
        NSLog("SmartIME: commit effect palette set to %@", choice.rawValue)
        previewCommitEffect()
    }

    /// Ignores Reduce Motion: the user just asked to see the effect.
    private func previewCommitEffect() {
        var generator = SystemRandomNumberGenerator()
        guard let skin = commitEffectSettings.resolve(reduceMotion: false, using: &generator) else {
            return
        }
        let pointer = NSEvent.mouseLocation
        withCandidatePanel { $0.previewCommitEffect(style: skin.style, palette: skin.palette, below: pointer) }
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

    /// Number keys pick candidates only when pressed alone: Shift+1 is "！", which librime commits after the
    /// first candidate.
    static func candidateIndex(forKeyCode keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Int? {
        guard modifierFlags.intersection([.shift, .control, .option, .command]).isEmpty else {
            return nil
        }
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
