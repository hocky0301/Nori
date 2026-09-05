import AppKit
import OSLog

/// Polls `NSPasteboard.general.changeCount`. There is no notification API for the
/// pasteboard on macOS, so every clipboard manager does exactly this.
@MainActor
final class ClipboardMonitor {
    enum Event: Sendable {
        case captured(ClipDraft, changeCount: Int)
        case rejected(CaptureRejection, changeCount: Int)
    }

    var policy: CapturePolicy = .default
    var isPaused = false
    /// Skip exactly one upcoming change (for "copy something private, just this once").
    var skipNextChange = false
    var onEvent: ((Event) -> Void)?

    private(set) var lastChangeCount: Int
    private var timer: Timer?
    private let pasteboard: NSPasteboard
    private let logger = Logger(subsystem: "io.github.hocky0301.Nori", category: "monitor")

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        lastChangeCount = pasteboard.changeCount
    }

    func start(interval: TimeInterval) {
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = interval / 4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Treat the current pasteboard contents as already seen (e.g. right after Nori wrote them).
    func markCurrentAsSeen() {
        lastChangeCount = pasteboard.changeCount
    }

    func poll() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let snapshot = PasteboardSnapshot.capture(from: pasteboard, sourceBundleID: source)

        if skipNextChange, !snapshot.hasNoriMarker {
            skipNextChange = false
            logger.info("skipped one change on request")
            return
        }
        if isPaused, !snapshot.hasNoriMarker {
            return
        }

        switch ClipClassifier.classify(snapshot, policy: policy) {
        case let .captured(draft):
            logger.info("captured \(draft.kind.rawValue, privacy: .public) (\(draft.byteCount) bytes) from \(source ?? "?", privacy: .public)")
            onEvent?(.captured(draft, changeCount: changeCount))
        case let .rejected(reason):
            logger.debug("rejected: \(String(describing: reason), privacy: .public)")
            onEvent?(.rejected(reason, changeCount: changeCount))
        }
    }
}
