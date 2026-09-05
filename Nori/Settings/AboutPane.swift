import AppKit
import SwiftUI

/// Settings › About: icon, version, links, license, credits.
struct AboutPane: View {
    static let repositoryURL = URL(string: "https://github.com/hocky0301/Nori")!
    static let maccyURL = URL(string: "https://github.com/p0deje/Maccy")!
    static let licenseURL = URL(string: "https://github.com/hocky0301/Nori/blob/main/LICENSE")!

    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "0"
        let build = info["CFBundleVersion"] as? String ?? "0"
        return String(localized: "Version \(short) (\(build))")
    }

    private var appName: String {
        (Bundle.main.infoDictionary?["CFBundleName"] as? String) ?? "Nori"
    }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appName)
                            .font(.title2.weight(.semibold))
                        Text(version)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("Clipboard history that shows every clip as what it is — and pastes it in one keystroke.")
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
            }
            Section {
                LabeledContent("Source code") {
                    Link("github.com/hocky0301/Nori", destination: Self.repositoryURL)
                }
                LabeledContent("Inspired by") {
                    Link("Maccy", destination: Self.maccyURL)
                }
                LabeledContent("License") {
                    Link("MIT License", destination: Self.licenseURL)
                }
            } footer: {
                Text("Built with Claude Code. Nori has no network access; clips never leave this Mac.")
            }
        }
        .formStyle(.grouped)
    }
}
