import CoreGraphics
import Vision

/// On-device text recognition (Vision) for Simplified and Traditional Chinese and English.
enum ScreenshotOCR {
    struct Line: Equatable {
        let text: String
        /// Normalized to the image, origin at the bottom left (Vision's convention).
        let box: CGRect
    }

    static let languages = ["zh-Hans", "zh-Hant", "en-US"]

    /// Runs off the main actor; a full-screen capture takes about a second.
    static func recognize(_ image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try recognizeLines(image)
        }.value
    }

    static func recognizeLines(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let lines = (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map { Line(text: $0.string, box: observation.boundingBox) }
        }
        return text(from: lines)
    }

    /// Lines top to bottom; pieces on the same row (their vertical centers inside each other's
    /// height) left to right, separated by a space.
    static func text(from lines: [Line]) -> String {
        var rows: [[Line]] = []
        for line in lines.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let last = rows.last?.first, abs(last.box.midY - line.box.midY) < min(last.box.height, line.box.height) / 2 {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows
            .map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
            .joined(separator: "\n")
    }
}
