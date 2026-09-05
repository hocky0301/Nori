import SwiftUI

/// Settings › Capture (§8): what to remember, limits, and the advanced ignore lists.
struct CapturePane: View {
    @Bindable var model: SettingsModel
    @State private var advancedExpanded = false

    private static let expiryOptions: [(days: Int, label: String)] = [
        (0, String(localized: "Never")), (1, String(localized: "1 day")), (7, String(localized: "1 week")), (30, String(localized: "1 month")),
    ]
    private static let imageSizeOptions = [5, 10, 25, 50]

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section("Remember") {
                Toggle("Text", isOn: $settings.captureText)
                Toggle("Images", isOn: $settings.captureImages)
                Toggle("Files", isOn: $settings.captureFiles)
            }
            Section {
                LabeledContent("Keep up to") {
                    HStack(spacing: 8) {
                        Text("\(settings.maxItems) clips")
                            .monospacedDigit()
                        Stepper("Keep up to", value: $settings.maxItems, in: 100...2000, step: 100)
                            .labelsHidden()
                    }
                }
                Picker("Forget clips older than", selection: $settings.expireAfterDays) {
                    ForEach(Self.expiryOptions, id: \.days) { option in
                        Text(option.label).tag(option.days)
                    }
                }
                Picker("Largest image to keep", selection: $settings.maxImageMegabytes) {
                    ForEach(Self.imageSizeOptions, id: \.self) { megabytes in
                        Text("\(megabytes) MB").tag(megabytes)
                    }
                }
            } footer: {
                Text("Pinned clips don't count toward the limit and never expire.")
            }
            Section {
                Toggle("Include copies from my iPhone and iPad", isOn: $settings.captureUniversalClipboard)
                Toggle(isOn: $settings.ocrImages) {
                    Text("Make screenshots searchable (OCR)")
                    Text("Text found in images is indexed on this Mac only.")
                }
            }
            Section {
                DisclosureGroup("Advanced", isExpanded: $advancedExpanded) {
                    Text("Ignored pasteboard types")
                        .font(.headline)
                        .padding(.top, 4)
                    StringListEditor(
                        items: $settings.ignoredTypes,
                        placeholder: "com.example.pasteboard-type",
                        restoreDefaults: { settings.ignoredTypes = PasteboardType.defaultIgnoredTypes },
                        emptyText: String(localized: "No types are ignored")
                    )
                    Text("Skip text matching these patterns")
                        .font(.headline)
                        .padding(.top, 8)
                    StringListEditor(
                        items: $settings.ignoreRegexps,
                        placeholder: String(localized: "Regular expression"),
                        isValid: SettingsSupport.isValidRegex,
                        emptyText: String(localized: "No patterns")
                    )
                }
            }
        }
        .formStyle(.grouped)
    }
}
