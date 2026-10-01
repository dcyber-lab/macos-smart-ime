import CoreGraphics
import SharedModels

struct CandidatePanelRow: Equatable {
    let label: String
    let text: String
    let tag: String?
    let isHighlighted: Bool
    let hasSeparatorBefore: Bool
    let annotation: String?
}

struct CandidatePanelHeader: Equatable {
    let text: String
    let canPageUp: Bool
    let canPageDown: Bool
}

enum CandidatePanelModel {
    static let maxAnnotationLength = 12

    /// Chinese mode shows the preedit above the rows; English mode already shows the typed text as row 1.
    static func header(for state: CompositionState) -> CandidatePanelHeader? {
        guard state.mode == .chinese, !state.compositionText.isEmpty else {
            return nil
        }
        return CandidatePanelHeader(
            text: state.compositionText,
            canPageUp: state.candidatePageIndex > 0,
            canPageDown: !state.isLastCandidatePage
        )
    }

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
                hasSeparatorBefore: isMixed && english != previousIsEnglish,
                annotation: candidate.annotation.map(truncated)
            )
        }
    }

    /// The row whose candidate was committed: an exact match (the highlighted row first), else the
    /// longest row text the commit starts with, which covers a trailing space ("deploy ") or
    /// punctuation ("你好，"). Nil when no row matches, e.g. raw pinyin committed with Return.
    static func committedRowIndex(in rows: [CandidatePanelRow], committedText: String) -> Int? {
        func best(_ indices: [Int]) -> Int? {
            indices.first { rows[$0].isHighlighted } ?? indices.first
        }
        let exact = rows.indices.filter { rows[$0].text == committedText }
        if let index = best(exact) {
            return index
        }
        let prefixes = rows.indices.filter { !rows[$0].text.isEmpty && committedText.hasPrefix(rows[$0].text) }
        let longest = prefixes.map { rows[$0].text.count }.max()
        return best(prefixes.filter { rows[$0].text.count == longest })
    }

    /// The same rows with only `index` highlighted.
    static func highlighting(_ rows: [CandidatePanelRow], at index: Int) -> [CandidatePanelRow] {
        rows.enumerated().map { i, row in
            CandidatePanelRow(label: row.label, text: row.text, tag: row.tag, isHighlighted: i == index,
                              hasSeparatorBefore: row.hasSeparatorBefore, annotation: row.annotation)
        }
    }

    /// The same rows with `index` left blank, for the panel's fade after that row broke away.
    static func vacating(_ rows: [CandidatePanelRow], at index: Int) -> [CandidatePanelRow] {
        rows.enumerated().map { i, row in
            i == index
                ? CandidatePanelRow(label: "", text: "", tag: nil, isHighlighted: false, hasSeparatorBefore: row.hasSeparatorBefore, annotation: nil)
                : row
        }
    }

    private static func truncated(_ annotation: String) -> String {
        annotation.count > maxAnnotationLength ? annotation.prefix(maxAnnotationLength) + "…" : annotation
    }

    private static func isEnglish(_ source: CandidateSource) -> Bool {
        switch source {
        case .englishCompletion, .englishTranslation:
            return true
        case .rime:
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
