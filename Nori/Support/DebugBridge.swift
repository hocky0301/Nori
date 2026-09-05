#if DEBUG
import AppKit
import Foundation

/// Lets scripts drive the app during development:
///   `notifyutil` cannot carry payloads, so we use DistributedNotificationCenter:
///   swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(.init("io.github.hocky0301.Nori.debug"), object: "open", userInfo: nil, deliverImmediately: true)'
/// Commands: open, close, toggle, seed, clear, screenshot:<path>, settings:<tab>, onboarding:<1|2|3>,
///   appearance:dark|light|system, mods:cmd|shift|opt|none, pin, delete, confirm-clear, banner, toast:<text>
///   (plus the model commands below)
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
        case let cmd where cmd.hasPrefix("select:"):
            // Deterministic selection for screenshots (hover would otherwise follow the pointer).
            if let n = Int(cmd.dropFirst("select:".count)), let row = coordinator.model.rows.filter({ !$0.row.isGhost })[safe: n - 1] {
                coordinator.model.select(id: row.id)
            }
        case "down": coordinator.model.moveSelection(by: 1)
        case "up": coordinator.model.moveSelection(by: -1)
        case "preview": coordinator.model.toggleExpanded()
        case "onboarding": coordinator.showOnboarding()
        case let cmd where cmd.hasPrefix("onboarding:"):
            if let step = Int(cmd.dropFirst("onboarding:".count)) { coordinator.showOnboarding(step: step) }
        case let cmd where cmd.hasPrefix("settings:"):
            if let tab = SettingsTab(rawValue: String(cmd.dropFirst("settings:".count))) { coordinator.openSettings(tab: tab) }
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
        if let png = Self.demoScreenshotPNG() {
            var draft = ClipClassifier.makeDraft(contents: [.init(type: PasteboardType.png, data: png)])!
            draft.sourceBundleID = "com.apple.screencaptureui"
            draft.sourceAppName = "Screenshot"
            history.ingest(draft, now: time)
        }
        let fileURL = URL(fileURLWithPath: "/Applications/Xcode.app")
        var fileDraft = ClipClassifier.makeDraft(contents: [.init(type: PasteboardType.fileURL, data: fileURL.dataRepresentation)])!
        fileDraft.sourceBundleID = "com.apple.finder"
        history.ingest(fileDraft, now: time.addingTimeInterval(60))
        if let last = history.rows.last { history.togglePin(id: last.id) }
    }
}

extension DebugBridge {
    /// A 1440×900 mock "app window" so image cards and previews look like a real screenshot.
    static func demoScreenshotPNG() -> Data? {
        let size = NSSize(width: 1440, height: 900)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [NSColor(calibratedRed: 0.18, green: 0.20, blue: 0.42, alpha: 1),
                                NSColor(calibratedRed: 0.55, green: 0.30, blue: 0.68, alpha: 1),
                                NSColor(calibratedRed: 0.98, green: 0.55, blue: 0.40, alpha: 1)])?
                .draw(in: rect, angle: -30)
            // A "window" with a title bar and three lines of "text".
            let window = NSRect(x: 180, y: 120, width: 1080, height: 640)
            NSColor(white: 1, alpha: 0.92).setFill()
            NSBezierPath(roundedRect: window, xRadius: 22, yRadius: 22).fill()
            NSColor(white: 0.93, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: window.minX, y: window.maxY - 52, width: window.width, height: 52), xRadius: 22, yRadius: 22).fill()
            for (i, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: window.minX + 22 + CGFloat(i) * 22, y: window.maxY - 33, width: 14, height: 14)).fill()
            }
            NSColor(white: 0.82, alpha: 1).setFill()
            for i in 0..<7 {
                let width = [620, 840, 480, 760, 700, 300, 560][i]
                NSBezierPath(roundedRect: NSRect(x: window.minX + 48, y: window.maxY - 120 - CGFloat(i) * 56, width: CGFloat(width), height: 20), xRadius: 10, yRadius: 10).fill()
            }
            NSColor(calibratedRed: 0.42, green: 0.38, blue: 0.98, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: window.minX + 48, y: window.minY + 48, width: 180, height: 44), xRadius: 12, yRadius: 12).fill()
            return true
        }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
#endif
