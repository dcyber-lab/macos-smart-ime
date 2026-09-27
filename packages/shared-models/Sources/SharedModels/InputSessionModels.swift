public enum CandidateSource: String, Sendable {
    case rime
    case englishCompletion
    case englishTranslation
}

public struct Candidate: Equatable, Sendable {
    public let text: String
    public let source: CandidateSource
    /// Short secondary text shown after the candidate, e.g. a Chinese gloss for an English word.
    public let annotation: String?

    public init(text: String, source: CandidateSource, annotation: String? = nil) {
        self.text = text
        self.source = source
        self.annotation = annotation
    }
}

public struct InputKeyEvent: Equatable, Sendable {
    public let keyCode: UInt16
    public let characters: String
    public let charactersIgnoringModifiers: String
    public let modifierFlags: UInt

    public init(
        keyCode: UInt16,
        characters: String,
        charactersIgnoringModifiers: String,
        modifierFlags: UInt = 0
    ) {
        self.keyCode = keyCode
        self.characters = characters
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
        self.modifierFlags = modifierFlags
    }
}

public enum InputMode: String, Sendable {
    case chinese
    case english
}

public struct CompositionState: Equatable, Sendable {
    public var rawInput: String
    public var mode: InputMode
    public var compositionText: String
    public var candidates: [Candidate]
    public var selectedCandidateIndex: Int?
    public var candidatePageIndex: Int
    public var isLastCandidatePage: Bool
    public var recentText: String

    public init(
        rawInput: String = "",
        mode: InputMode = .chinese,
        compositionText: String = "",
        candidates: [Candidate] = [],
        selectedCandidateIndex: Int? = nil,
        candidatePageIndex: Int = 0,
        isLastCandidatePage: Bool = true,
        recentText: String = ""
    ) {
        self.rawInput = rawInput
        self.mode = mode
        self.compositionText = compositionText
        self.candidates = candidates
        self.selectedCandidateIndex = selectedCandidateIndex
        self.candidatePageIndex = candidatePageIndex
        self.isLastCandidatePage = isLastCandidatePage
        self.recentText = recentText
    }
}

public struct InputSessionUpdate: Equatable, Sendable {
    public let handled: Bool
    public let state: CompositionState
    public let commitText: String?

    public init(handled: Bool, state: CompositionState, commitText: String? = nil) {
        self.handled = handled
        self.state = state
        self.commitText = commitText
    }
}

public protocol ChineseInputEngine: AnyObject {
    func process(_ event: InputKeyEvent) -> InputSessionUpdate
    func selectCandidate(at index: Int) -> InputSessionUpdate
    func highlightCandidate(at index: Int) -> InputSessionUpdate
    func reset()
}

public protocol EnglishInputEngine: AnyObject {
    func process(_ event: InputKeyEvent) -> InputSessionUpdate
    func selectCandidate(at index: Int) -> InputSessionUpdate
    func highlightCandidate(at index: Int) -> InputSessionUpdate
    func reset()
}
