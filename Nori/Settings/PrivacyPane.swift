import SwiftUI

/// Settings › Privacy (§8): ignored apps, secret masking, ghost rows, clear-on-quit, storage, clear.
struct PrivacyPane: View {
    @Bindable var model: SettingsModel
    @State private var advancedExpanded = false
    @State private var isClearAlertVisible = false
    @State private var clearIncludesPinned = false
    @State private var storageSummary = ""
    @State private var optionKey = OptionKeyMonitor()

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section("Don't remember copies from") {
                // Bounded and scrolling, so a long list doesn't grow the window off screen.
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if settings.ignoredApps.isEmpty {
                            Text("No apps are ignored")
                                .foregroundStyle(.tertiary)
                                .padding(.vertical, 10)
                        }
                        ForEach(settings.ignoredApps, id: \.self) { bundleID in
                            IgnoredAppRow(bundleID: bundleID) {
                                settings.ignoredApps.removeAll { $0 == bundleID }
                            }
                            .padding(.vertical, 6)
                            if bundleID != settings.ignoredApps.last {
                                Divider()
                            }
                        }
                    }
                }
                .frame(height: 176)
                HStack(spacing: 12) {
                    Button {
                        addApp()
                    } label: {
                        Label("Add App…", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    Button("Restore defaults") {
                        settings.ignoredApps = PasteboardType.defaultIgnoredApps
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                }
                .font(.callout)
            }
            Section {
                Toggle(isOn: $settings.maskSensitive) {
                    Text("Hide things that look like passwords or API keys")
                    Text("Shown masked, never saved to disk, forgotten after 10 minutes")
                }
                Toggle("Show a note in the list when something wasn't saved", isOn: $settings.showGhostRows)
                Toggle("Clear history when Nori quits", isOn: $settings.clearOnQuit)
            }
            Section {
                DisclosureGroup("Advanced", isExpanded: $advancedExpanded) {
                    Toggle("Clearing history also clears the system clipboard", isOn: $settings.clearSystemClipboardOnClear)
                }
            }
            Section {
                LabeledContent("Storage used") {
                    Text(storageSummary)
                        .monospacedDigit()
                }
                LabeledContent("History") {
                    Button(optionKey.isOptionHeld ? "Clear Including Pinned…" : "Clear History…") {
                        clearIncludesPinned = optionKey.isOptionHeld
                        isClearAlertVisible = true
                    }
                    .disabled(model.history.count == 0)
                }
            } footer: {
                Text("Clips are stored unencrypted in Nori's container in ~/Library. Use Pause for sensitive work.")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            optionKey.start()
            storageSummary = model.storageSummary
        }
        .onDisappear { optionKey.stop() }
        .onChange(of: model.history.version) { storageSummary = model.storageSummary }
        .task(id: model.isWindowVisible) {
            guard model.isWindowVisible else { return }
            while !Task.isCancelled {
                storageSummary = model.storageSummary
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .alert(
            clearIncludesPinned ? "Clear history including pinned clips?" : "Clear history?",
            isPresented: $isClearAlertVisible
        ) {
            Button(clearIncludesPinned ? "Clear Including Pinned" : "Clear", role: .destructive) {
                model.clearHistory(includingPinned: clearIncludesPinned)
                storageSummary = model.storageSummary
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(clearMessage)
        }
    }

    private var clearMessage: String {
        let count = model.history.count
        let pinned = model.history.pinnedCount
        if clearIncludesPinned {
            return String(inflected: "^[\(count) clip](inflect: true) will be removed, including ^[\(pinned) pinned clip](inflect: true). This can't be undone.")
        }
        let unpinned = count - pinned
        return String(inflected: "^[\(unpinned) clip](inflect: true) will be removed. ^[\(pinned) pinned clip](inflect: true) will stay.")
    }

    private func addApp() {
        AppPicker.pick(from: model.window) { bundleID in
            guard let bundleID, !bundleID.isEmpty else { return }
            if !model.settings.ignoredApps.contains(bundleID) {
                model.settings.ignoredApps.append(bundleID)
            }
        }
    }
}

/// One ignored app: icon and name when installed, the bare bundle id otherwise.
private struct IgnoredAppRow: View {
    let bundleID: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let app = SettingsSupport.installedApp(bundleID: bundleID) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                    Text(bundleID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "app.dashed")
                    .frame(width: 20, height: 20)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(bundleID)
                    Text("Not installed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: remove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Remove")
        }
    }
}
