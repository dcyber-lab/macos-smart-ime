import CoreGraphics
import SharedModels

struct CandidatePanelRow: Equatable {
    let label: String
    let text: String
    let tag: String?
    let isHighlighted: Bool
    let hasSeparatorBefore: Bool
}

enum CandidatePanelModel {
    /// Tags and separators only appear when Chinese and English candidates are mixed.
    static func rows(for state: CompositionState) -> [CandidatePanelRow] {
        let candidates = state.candidates
        let isMixed = candidates.contains { isEnglish($0.source) } && candidates.contains { !isEnglish($0.source) }

        return candidates.enumerated().map { index, candidate in
            let english = isEnglish(candidate.source)
            let previousIsEnglish = index > 0 ? isEnglish(candidates[index - 1].source) : english
            return CandidatePanelRow(
                label: String(index + 1),
                text: candidate.text,
                tag: isMixed && english ? tag(for: candidate.source) : nil,
                isHighlighted: index == state.selectedCandidateIndex,
                hasSeparatorBefore: isMixed && english != previousIsEnglish
            )
        }
    }

    private static func isEnglish(_ source: CandidateSource) -> Bool {
        switch source {
        case .englishCompletion, .englishCorrection, .englishTranslation:
            return true
        case .rime, .placeholder:
            return false
        }
    }

    private static func tag(for source: CandidateSource) -> String {
        source == .englishTranslation ? "译" : "英"
    }
}

enum CandidatePanelPlacement {
    static let caretGap: CGFloat = 4

    /// Screen coordinates (origin bottom-left). Below the caret, above it when there is no room, clamped horizontally.
    static func origin(panelSize: CGSize, caretRect: CGRect, visibleFrame: CGRect) -> CGPoint {
        var y = caretRect.minY - caretGap - panelSize.height
        if y < visibleFrame.minY {
            y = min(caretRect.maxY + caretGap, visibleFrame.maxY - panelSize.height)
        }
        let x = min(max(caretRect.minX, visibleFrame.minX), visibleFrame.maxX - panelSize.width)
        return CGPoint(x: x, y: y)
    }

    /// Clients that cannot report a caret return an empty rectangle at the origin.
    static func caretRect(reported: CGRect, lastKnown: CGRect?, mouseLocation: CGPoint) -> CGRect {
        if reported.height > 0, reported.origin != .zero {
            return reported
        }
        return lastKnown ?? CGRect(origin: mouseLocation, size: .zero)
    }
}
