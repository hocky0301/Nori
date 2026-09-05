#if DEBUG
import AppKit
import Foundation

/// Lets scripts drive the app during development:
///   `notifyutil` cannot carry payloads, so we use DistributedNotificationCenter:
///   swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(.init("io.github.hocky0301.Nori.debug"), object: "open", userInfo: nil, deliverImmediately: true)'
/// Commands: open, close, toggle, seed, clear, screenshot:<path>, appearance:dark|light|system, mods:cmd|shift|opt|none,
///   pin, delete, confirm-clear, banner, toast:<text> (plus the model commands below)
@MainActor
final class DebugBridge {
    /// `--debug-channel=NAME` isolates parallel dev instances (each listens on its own name).
    static var notificationName: Notification.Name {
        let channel = CommandLine.arguments.first { $0.hasPrefix("--debug-channel=") }?
            .dropFirst("--debug-channel=".count) ?? ""
        return Notification.Name("io.github.hocky0301.Nori.debug" + (channel.isEmpty ? "" : ".\(channel)"))
    }
    private unowned let coordinator: AppCoordinator
    private var token: (any NSObjectProtocol)?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        token = DistributedNotificationCenter.default().addObserver(
            forName: Self.notificationName, object: nil, queue: .main
        ) { [weak self] note in
            let command = note.object as? String ?? ""
            MainActor.assumeIsolated { self?.handle(command) }
        }
        if CommandLine.arguments.contains("--seed-demo") {
            seedDemoData()
        }
    }

    private func handle(_ command: String) {
        switch command {
        case "open": coordinator.panelController.open()
        case "open-center": coordinator.panelController.open(position: .center)
        case "close": coordinator.panelController.close()
        case "toggle": coordinator.togglePanel()
        case "seed": seedDemoData()
        case "clear": coordinator.history.clear(includingPinned: true); coordinator.vault.removeAll()
        case "settings": coordinator.openSettings()
        case let cmd where cmd.hasPrefix("screenshot:"):
            screenshot(to: String(cmd.dropFirst("screenshot:".count)))
        case let cmd where cmd.hasPrefix("query:"):
            coordinator.model.query = String(cmd.dropFirst("query:".count))
        case let cmd where cmd.hasPrefix("filter:"):
            if let filter = PanelFilter(rawValue: String(cmd.dropFirst("filter:".count))) { coordinator.model.filter = filter }
        case "down": coordinator.model.moveSelection(by: 1)
        case "up": coordinator.model.moveSelection(by: -1)
        case "preview": coordinator.model.toggleExpanded()
        case "onboarding": coordinator.showOnboarding()
        case "ghost": coordinator.model.addGhost(.concealed(appName: "1Password"), at: .now)
        case "pause": coordinator.pauseCapture(until: .now.addingTimeInterval(1800))
        case "resume": coordinator.resumeCapture()
        case "appearance:dark": coordinator.panelController.panel.appearance = NSAppearance(named: .darkAqua)
        case "appearance:light": coordinator.panelController.panel.appearance = NSAppearance(named: .aqua)
        case "appearance:system": coordinator.panelController.panel.appearance = nil
        case "mods:cmd": coordinator.model.debugSetModifierBits([.copyOnly])
        case "mods:shift": coordinator.model.debugSetModifierBits([.plain])
        case "mods:opt": coordinator.model.debugSetModifierBits([.keepOpen])
        case "mods:none": coordinator.model.debugSetModifierBits([])
        case "pin": coordinator.model.togglePinSelected()
        case "delete": coordinator.model.deleteSelected()
        case "confirm-clear": coordinator.model.showClearConfirmation()
        case "banner": coordinator.model.showsAccessibilityBanner = true
        case let cmd where cmd.hasPrefix("toast:"):
            coordinator.model.showToast(String(cmd.dropFirst("toast:".count)))
        default: NSLog("DebugBridge: unknown command \(command)")
        }
    }

    /// Render the panel's content view to a PNG (no screen-recording permission needed).
    private func screenshot(to path: String) {
        guard let view = coordinator.panelController.panel.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }

    func seedDemoData() {
        let history = coordinator.history
        func text(_ s: String, app: String) -> ClipDraft {
            var draft = ClipClassifier.makeDraft(contents: [.init(type: PasteboardType.utf8PlainText, data: Data(s.utf8))], sourceBundleID: app)!
            draft.sourceBundleID = app
            draft.sourceAppName = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app)
                .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
            return draft
        }
        let samples: [ClipDraft] = [
            text("https://developer.apple.com/documentation/swiftui/glasseffectcontainer", app: "com.apple.Safari"),
            text("brew install --cask nori", app: "com.apple.Terminal"),
            text("#5E5CE6", app: "com.figma.Desktop"),
            text("""
            struct ContentView: View {
                var body: some View {
                    Text("Hello, Nori!")
                        .glassEffect()
                }
            }
            """, app: "com.apple.dt.Xcode"),
            text("Nori keeps the history of what you copy and lets you find it again in a keystroke. Everything stays on your Mac.", app: "com.apple.Notes"),
            text("kamil.ijuin@example.com", app: "com.apple.mail"),
            text("rgb(255, 122, 89)", app: "com.apple.Safari"),
            text("Meeting moved to 15:30 — bring the Q3 numbers and the updated roadmap.", app: "com.tinyspeck.slackmacgap"),
            text("git rebase -i HEAD~3", app: "com.apple.Terminal"),
            text("https://zenn.dev/", app: "com.google.Chrome"),
        ]
        var time = Date.now.addingTimeInterval(-3600)
        for draft in samples.reversed() {
            history.ingest(draft, now: time)
            time = time.addingTimeInterval(240)
        }
        // Yesterday and earlier, for the section headers.
        history.ingest(text("Yesterday's note: ship the README before the article.", app: "com.apple.Notes"), now: .now.addingTimeInterval(-86_400))
        history.ingest(text("Three days ago: xcodegen generate && open Nori.xcodeproj", app: "com.apple.Terminal"), now: .now.addingTimeInterval(-3 * 86_400))
        // A secret: masked, in memory only.
        var secret = text("ghp_abcdefghijklmnopqrstuvwxyz0123456789ABCD", app: "com.apple.Safari")
        secret.sourceAppName = "Safari"
        coordinator.vault.add(SensitiveDraft(match: .gitHubToken, mask: SecretDetector.mask(secret.plainText ?? ""), draft: secret))
        if let image = NSImage(systemSymbolName: "photo.artframe", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 160, weight: .regular)),
           let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            var draft = ClipClassifier.makeDraft(contents: [.init(type: PasteboardType.png, data: png)])!
            draft.sourceBundleID = "com.apple.Preview"
            history.ingest(draft, now: time)
        }
        let fileURL = URL(fileURLWithPath: "/Applications/Safari.app")
        var fileDraft = ClipClassifier.makeDraft(contents: [.init(type: PasteboardType.fileURL, data: fileURL.dataRepresentation)])!
        fileDraft.sourceBundleID = "com.apple.finder"
        history.ingest(fileDraft, now: time.addingTimeInterval(60))
        if let last = history.rows.last { history.togglePin(id: last.id) }
    }
}
#endif
