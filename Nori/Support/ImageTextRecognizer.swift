import Foundation
import Vision

/// Runs fast OCR on captured images so screenshots become searchable.
///
/// Requests run one at a time — each holds a full-size PNG plus Vision's working set — and an
/// item is read at most once, so a burst of screenshots or a re-copy never fans out.
@MainActor
enum ImageTextRecognizer {
    private static var chain: Task<Void, Never>?
    private static var queued: Set<UUID> = []

    /// `isStillWanted` runs right before the request: it returns false for an item that was
    /// evicted meanwhile or already has searchable text.
    static func recognize(
        itemID: UUID,
        imageData: Data?,
        isStillWanted: @escaping @MainActor (UUID) -> Bool,
        completion: @escaping @MainActor (UUID, String) -> Void
    ) {
        guard let imageData, !queued.contains(itemID) else { return }
        if queued.count > 1_000 { queued.removeAll() }
        queued.insert(itemID)
        let previous = chain
        chain = Task {
            await previous?.value
            guard isStillWanted(itemID) else { return }
            let text = await Task.detached(priority: .utility) { recognizeText(in: imageData) }.value
            guard let text, !text.isEmpty else { return }
            completion(itemID, text)
        }
    }

    nonisolated private static func recognizeText(in imageData: Data) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(data: imageData)
        guard (try? handler.perform([request])) != nil else { return nil }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }
}
