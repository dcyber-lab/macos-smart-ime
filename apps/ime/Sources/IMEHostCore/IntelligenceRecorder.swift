import Foundation
import UserData

/// Feeds committed text into the input memory and journal, under the privacy rules: nothing while
/// learning is off, in excluded apps, or under secure input; sensitive sentences are dropped whole.
/// Called on commit only, never per keystroke.
final class IntelligenceRecorder {
    let settings: IntelligenceSettings
    let memory: InputMemory
    let journal: InputJournal
    private let assembler = SentenceAssembler()
    private let clock: () -> Date

    init(settings: IntelligenceSettings, memory: InputMemory, journal: InputJournal, clock: @escaping () -> Date = { Date() }) {
        self.settings = settings
        self.memory = memory
        self.journal = journal
        self.clock = clock
        assembler.onSentence = { [weak self] sentence in
            self?.learn(sentence)
        }
    }

    func commit(_ text: String, app: String?, secureInput: Bool) {
        guard settings.isLearningEnabled, !secureInput, let app, settings.allows(app: app) else {
            // Leaving an allowed app still closes what was typed there.
            assembler.endSentence()
            return
        }
        assembler.commit(text, app: app, at: clock())
    }

    /// `Return` without a composition, or the input method losing focus.
    func endSentence() {
        assembler.endSentence()
    }

    func recentSentences(in app: String) -> [String] {
        assembler.recent[app] ?? []
    }

    /// Deletes everything learned, on disk and in memory.
    func clear() {
        assembler.forgetRecent()
        memory.clear()
        journal.clear()
    }

    private func learn(_ sentence: SentenceAssembler.Sentence) {
        guard PrivacyFilter.allowsSentence(sentence.text) else {
            return
        }
        memory.record(sentence: sentence.text, app: sentence.app)
        if settings.isJournalEnabled {
            journal.append(sentence.text, app: sentence.app)
        }
    }
}
