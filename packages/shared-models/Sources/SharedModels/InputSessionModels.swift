public enum CandidateSource: String, Sendable {
    case placeholder
    case rime
    case englishCompletion
    case englishCorrection
}

public struct Candidate: Equatable, Sendable {
    public let text: String
    public let source: CandidateSource
    public let score: Double

    public init(text: String, source: CandidateSource, score: Double) {
        self.text = text
        self.source = source
        self.score = score
    }
}

public enum InputMode: String, Sendable {
    case chinese
    case english
    case mixed
}

public struct CompositionState: Equatable, Sendable {
    public var rawInput: String
    public var mode: InputMode
    public var compositionText: String
    public var candidates: [Candidate]
    public var recentText: String

    public init(
        rawInput: String = "",
        mode: InputMode = .chinese,
        compositionText: String = "",
        candidates: [Candidate] = [],
        recentText: String = ""
    ) {
        self.rawInput = rawInput
        self.mode = mode
        self.compositionText = compositionText
        self.candidates = candidates
        self.recentText = recentText
    }
}
