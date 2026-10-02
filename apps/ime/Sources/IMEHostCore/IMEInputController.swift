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
    /// AI assist (proof of concept): a ✨ rewrite offered after sentences in apps the user enabled.
    @MainActor private static let aiChip = AIAssistChipController(
        rewriter: { AIAssistSettings().rewriter() },
        present: { display, caret in SuggestionChip.shared.show(display, caret: caret) },
        log: { event, app in AIAssistEventLog.shared.append(event, app: app) }
    )
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
    /// Where the AI rewrite popup is anchored (start of the text being rewritten).
    private var aiRewriteAnchor = NSRect.zero
    private lazy var aiRewrite = MainActor.assumeIsolated {
        AIRewriteController(rewriter: { AIAssistSettings().rewriter() }) { [weak self] state in
            TranslationPopup.shared.show(state, caretRect: self?.aiRewriteAnchor ?? .zero)
        }
    }
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

        // While a ✨ chip shows: Tab accepts, Esc dismisses, any other key dismisses and is typed.
        let keyCode = event.keyCode
        if MainActor.assumeIsolated({ Self.aiChip.handleKey(keyCode) }) == .consumed {
            return true
        }

        if Self.returnKeys.contains(event.keyCode), !sessionStore.hasActiveComposition {
            // Reads the field before the app gets the key: a chat app sends and clears it on Return.
            let app = clientBundleIdentifier, secureInput = IsSecureEventInputEnabled(), readTitle = windowTitleReader()
            MainActor.assumeIsolated {
                Self.intelligence.endLine(app: app, secureInput: secureInput,
                                          readField: { [weak self] in self?.textBeforeCursor() }, readWindowTitle: readTitle)
            }
        }

        if let handled = handleAIRewriteKey(event) {
            return handled
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
            Self.intelligence.onFieldSentence = { [weak self] end in self?.offerAIRewrite(end) }
            Self.translationLearner.runIfDue()
            if Date().timeIntervalSince(Self.lastJournalPrune) > 24 * 60 * 60 {
                Self.lastJournalPrune = Date()
                Self.intelligence.journal.prune(keepingDays: Self.intelligence.settings.retentionDays)
            }
        }
    }

    public override func deactivateServer(_ sender: Any!) {
        // An unfinished sentence stays open: leaving to copy a link and coming back continues it.
        MainActor.assumeIsolated { Self.aiChip.dismiss(reason: "dismissed on deactivation") }
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
        MainActor.assumeIsolated {
            selectionTranslation.dismiss()
            // Its range belongs to this field: Return in the next one must not replace there.
            aiRewrite.dismiss()
        }
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
            let app = clientBundleIdentifier, secureInput = IsSecureEventInputEnabled(), readTitle = windowTitleReader()
            let session = ObjectIdentifier(self).hashValue
            MainActor.assumeIsolated {
                Self.intelligence.commit(committedText, app: app, session: session, secureInput: secureInput,
                                         readField: { [weak self] in self?.textBeforeCursor() }, readWindowTitle: readTitle)
            }
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
        IntelligenceMenu.items(settings: IntelligenceSettings(), currentApp: currentApp, isAccessibilityTrusted: WindowTitleReader.isTrusted,
                               action: #selector(intelligenceMenuCommand(_:)))
            .forEach(menu.addItem)
        menu.addItem(.separator())
        let ai = AIAssistSettings()
        AIAssistMenu.items(settings: ai, currentApp: currentApp, active: ai.activeProvider(), action: #selector(aiMenuCommand(_:)))
            .forEach(menu.addItem)
        return menu
    }

    @objc func aiMenuCommand(_ sender: Any?) {
        let settings = AIAssistSettings()
        switch AIAssistMenu.command(from: sender) {
        case .toggleChips:
            if let app = clientBundleIdentifier {
                settings.toggleChips(in: app)
            }
        case .provider(let provider):
            settings.provider = provider
        case nil:
            NSLog("SmartIME: unrecognized AI menu item: %@", String(describing: sender))
        }
    }

    // MARK: AI assist

    /// ⌃⌥R starts a rewrite; while its popup is open, keys go to it first.
    private func handleAIRewriteKey(_ event: NSEvent) -> Bool? {
        let keyCode = event.keyCode
        let outcome = MainActor.assumeIsolated { aiRewrite.isActive ? aiRewrite.handleKey(keyCode) : nil }
        switch outcome {
        case .replace(let text, let range, let original)?:
            let outcome = replaceText(in: range, with: text, expecting: original)
            if outcome != .replaced {
                MainActor.assumeIsolated { aiRewrite.report(outcome.message) }
            }
            return true
        case .handled?, .dismissed(consumed: true)?, .copy?:
            return true
        case .dismissed(consumed: false)?, nil:
            break
        }
        let settings = AIAssistSettings()
        guard settings.hotkey.matches(keyCode: keyCode, modifierFlags: event.modifierFlags), !sessionStore.hasActiveComposition else {
            return nil
        }
        startAIRewrite()
        return true
    }

    /// The selection, or the line before the cursor; nothing is sent until an action is picked.
    private func startAIRewrite() {
        let app = clientBundleIdentifier
        let blocked = IsSecureEventInputEnabled() || !IntelligenceSettings().allows(app: app) && !AIAssistSettings().chipApps.contains(app ?? "")
        let client = self.client()
        var text: String?
        var range = NSRange(location: NSNotFound, length: 0)
        var truncated = false
        if !blocked, let client {
            let selection = client.selectedRange()
            if selection.location != NSNotFound, selection.length > 0 {
                range = selection
                text = client.attributedSubstring(from: selection)?.string
            } else if let field = textBeforeCursor(), let line = AIRewriteController.line(before: field) {
                text = line.text
                range = line.range
                truncated = line.truncated
            }
            var anchor = NSRect.zero
            if range.location != NSNotFound {
                _ = client.attributes(forCharacterIndex: range.location, lineHeightRectangle: &anchor)
            }
            aiRewriteAnchor = anchor.height > 0 ? anchor : caretRect()
        }
        let start = (text: text, range: range, truncated: truncated)
        MainActor.assumeIsolated {
            if !blocked && start.text == nil {
                // A page without a text field reports nothing; copy the selection instead.
                GlobalSelectionAssist.shared.startReadOnly()
            } else if blocked {
                aiRewrite.start(text: nil, range: range)
            } else {
                aiRewrite.start(text: start.text, range: start.range, truncated: start.truncated)
            }
        }
    }

    /// Offers ✨ 转成英文 for a sentence that just ended, if this app has AI hints on and it qualifies.
    private func offerAIRewrite(_ end: FieldSentenceEnd) {
        guard AIAssistSettings().chipApps.contains(end.app), AIAssistChipController.qualifies(end.text),
              !sessionStore.hasActiveComposition, end.app == clientBundleIdentifier else {
            return
        }
        let length = (end.text as NSString).length
        guard end.cursor >= length else {
            return
        }
        let offer = AIAssistChipController.Offer(
            app: end.app, sentence: end.text, range: NSRange(location: end.cursor - length, length: length), caret: caretRect(),
            apply: { [weak self] text, range in self?.replaceText(in: range, with: text, expecting: end.text) ?? .refused }
        )
        MainActor.assumeIsolated { Self.aiChip.offer(offer) }
    }

    /// Replaces the range in the client if it still holds `original` (the user may have clicked elsewhere
    /// or edited), and checks that it took; otherwise copies the text so the user can paste it.
    private func replaceText(in range: NSRange, with text: String, expecting original: String) -> AIReplacement {
        let outcome: AIReplacement
        if let client = client(), client.attributedSubstring(from: range)?.string == original {
            client.insertText(text, replacementRange: range)
            let written = client.attributedSubstring(from: NSRange(location: range.location, length: (text as NSString).length))?.string
            outcome = written == text ? .replaced : .refused
        } else {
            outcome = .textChanged
        }
        if outcome != .replaced {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        return outcome
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
                    Self.intelligence.closeQuietly()
                }
            case .journal:
                settings.isJournalEnabled.toggle()
            case .windowTitles:
                settings.isWindowTitlesEnabled.toggle()
                if settings.isWindowTitlesEnabled, !WindowTitleReader.isTrusted {
                    WindowTitleReader.requestTrust()
                }
            case .excludeApp:
                if let app {
                    Self.intelligence.closeQuietly()
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

    /// Reads the client app's focused window title when that setting is on; nil otherwise.
    private func windowTitleReader() -> (() -> String?)? {
        guard let app = clientBundleIdentifier, IntelligenceSettings().isWindowTitlesEnabled else {
            return nil
        }
        return { WindowTitleReader.focusedWindowTitle(bundleIdentifier: app) }
    }

    /// How many characters before the cursor each app answered for; Chromium-based apps (Electron:
    /// SeaTalk, Slack, VS Code) return nothing for more than about 100.
    @MainActor private static var fieldReadLimits: [String: Int] = [:]
    private static let fieldReadSizes = [1_300, 100]

    /// Text before the cursor in the client's field (a long sentence plus context), through the IMK
    /// text input calls selection translation uses. A round trip to the client app: only called when a
    /// sentence ends. Tries the larger size first and remembers what works for each app.
    private func textBeforeCursor() -> FieldText? {
        guard let client = client() else {
            return nil
        }
        let cursor = client.selectedRange()
        guard cursor.location != NSNotFound, cursor.location > 0 else {
            return nil
        }
        let app = clientBundleIdentifier ?? ""
        let known = MainActor.assumeIsolated { Self.fieldReadLimits[app] }
        for size in known.map({ [$0] }) ?? Self.fieldReadSizes {
            let start = max(0, cursor.location - size)
            let range = NSRange(location: start, length: cursor.location - start)
            if let text = client.attributedSubstring(from: range)?.string, !text.isEmpty {
                MainActor.assumeIsolated { Self.fieldReadLimits[app] = size }
                return FieldText(text, startsMidway: start > 0, cursor: cursor.location)
            }
        }
        // Nothing at any size (a terminal, say): try only the small read from now on.
        MainActor.assumeIsolated { Self.fieldReadLimits[app] = Self.fieldReadSizes.last }
        return nil
    }

    /// App names are looked up here; tokenizing, date detection, and writing run in the background.
    @MainActor private static func openLearningPage() {
        let settings = intelligence.settings
        let summary = intelligence.memory.summary()
        let entries = intelligence.journal.entries(days: settings.retentionDays)
        let apps = Set(summary.apps.map(\.bundleIdentifier) + entries.map(\.app) + intelligence.contextStats.keys + intelligence.windowStats.keys)
        let names = Dictionary(uniqueKeysWithValues: apps.map { ($0, AppNames.displayName(for: $0)) })
        let input = LearningPage.Input(
            isLearningEnabled: settings.isLearningEnabled,
            isJournalEnabled: settings.isJournalEnabled,
            retentionDays: settings.retentionDays,
            excludedApps: settings.effectiveExcludedApps.map(AppNames.displayName(for:)).sorted(),
            summary: summary,
            entries: entries,
            insights: LearningInsights(),
            contextStats: intelligence.contextStats,
            windowStats: intelligence.windowStats,
            isWindowTitlesEnabled: settings.isWindowTitlesEnabled,
            isAccessibilityTrusted: WindowTitleReader.isTrusted,
            appName: { names[$0] ?? $0 },
            generatedAt: Date()
        )
        let url = IMEHostConfiguration.learningPageURL()
        DispatchQueue.global(qos: .userInitiated).async {
            var page = input
            page.insights = LearningInsights.compute(entries: entries, summary: summary)
            PrivateFiles.write(Data(LearningPage.html(page).utf8), to: url)
            DispatchQueue.main.async {
                NSWorkspace.shared.open(url)
            }
        }
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
