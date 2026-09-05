import AppKit
import OSLog

/// Polls `NSPasteboard.general.changeCount`. There is no notification API for the
/// pasteboard on macOS, so every clipboard manager does exactly this.
@MainActor
final class ClipboardMonitor {
    enum Event: Sendable {
        case captured(ClipDraft)
        case sensitive(SensitiveDraft)
        case ghost(GhostReason, at: Date)
        case promoted(UUID)
        case rejected(CaptureRejection)
    }

    var policy: CapturePolicy = .default
    /// nil = running; `.distantFuture` = until resumed; otherwise resume automatically at that date.
    var pausedUntil: Date?
    /// Skip exactly one upcoming change (for "copy something private, just this once").
    var skipNextChange = false
    var onEvent: ((Event) -> Void)?

    private(set) var lastChangeCount: Int
    private var timer: Timer?
    private let pasteboard: NSPasteboard
    private var activity: (any NSObjectProtocol)?
    private let logger = Logger(subsystem: "io.github.hocky0301.Nori", category: "monitor")

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        lastChangeCount = pasteboard.changeCount
    }

    var isPaused: Bool {
        guard let pausedUntil else { return false }
        return pausedUntil > .now
    }

    func start(interval: TimeInterval) {
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = interval / 4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        if activity == nil {
            // Without this App Nap coalesces the timer to once every few seconds after a few idle minutes.
            activity = ProcessInfo.processInfo.beginActivity(options: [.background], reason: "Clipboard monitoring")
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Treat the current pasteboard contents as already seen (e.g. right after Nori wrote them).
    func markCurrentAsSeen() {
        lastChangeCount = pasteboard.changeCount
    }

    /// Check now (also called when the panel opens so a copy made a moment ago is never missing).
    func poll() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        let snapshot = PasteboardSnapshot.capture(from: pasteboard, source: NSWorkspace.shared.frontmostApplication)

        if skipNextChange, !snapshot.hasNoriMarker {
            skipNextChange = false
            logger.info("skipped one change on request")
            return
        }
        if isPaused, !snapshot.hasNoriMarker {
            return
        }

        let policy = self.policy
        Task.detached(priority: .userInitiated) { [weak self] in
            let outcome = ClipClassifier.classify(snapshot, policy: policy)
            await self?.deliver(outcome, capturedAt: snapshot.capturedAt)
        }
    }

    private func deliver(_ outcome: CaptureOutcome, capturedAt: Date) {
        switch outcome {
        case let .captured(draft):
            logger.info("captured \(draft.kind.rawValue, privacy: .public) (\(draft.byteCount) bytes)")
            onEvent?(.captured(draft))
        case let .sensitive(sensitive):
            logger.info("sensitive \(sensitive.match.rawValue, privacy: .public) kept in memory")
            onEvent?(.sensitive(sensitive))
        case let .ghost(reason):
            logger.info("ghost: \(reason.message, privacy: .public)")
            onEvent?(.ghost(reason, at: capturedAt))
        case let .rejected(.fromNori(id)):
            if let id { onEvent?(.promoted(id)) }
        case let .rejected(reason):
            logger.debug("rejected: \(String(describing: reason), privacy: .public)")
            onEvent?(.rejected(reason))
        }
    }
}
