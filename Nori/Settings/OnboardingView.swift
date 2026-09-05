import SwiftUI

/// Placeholder until the onboarding UI lands: a single Done button.
struct OnboardingView: View {
    let coordinator: AppCoordinator
    let finish: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Welcome to Nori").font(.title2.weight(.semibold))
            Text("Press ⌘⇧V anywhere to open your clipboard history.").foregroundStyle(.secondary)
            Button("Done", action: finish).keyboardShortcut(.defaultAction)
        }
        .frame(width: 520, height: 440)
    }
}
