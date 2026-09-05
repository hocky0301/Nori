import Foundation
import Vision

/// Runs fast OCR on captured images so screenshots become searchable.
enum ImageTextRecognizer {
    static func recognize(itemID: UUID, imageData: Data?, completion: @escaping @MainActor (UUID, String) -> Void) {
        guard let imageData else { return }
        Task.detached(priority: .utility) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(data: imageData)
            guard (try? handler.perform([request])) != nil else { return }
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            let text = lines.joined(separator: "\n")
            guard !text.isEmpty else { return }
            await completion(itemID, text)
        }
    }
}
