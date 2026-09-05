import OndKit
import OndUI
import SwiftUI

struct AssistantConsentView: View {
    @Environment(AssistantConsentStore.self) private var consent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
                if consent.isAllowed {
                    Text("AI sharing is allowed").font(.title2)
                    Text("You can withdraw this permission in Settings at any time.")
                    Button("Done") { dismiss() }.buttonStyle(.inkAction)
                } else {
                    Text("Before you ask the coach").font(.title2).accessibilityAddTraits(.isHeader)
                    Text(AssistantConsentStore.disclosure)
                    Text("AI can make mistakes. The coach is not medical advice.")
                        .font(.subheadline).foregroundStyle(Theme.Ink.secondary)
                    Button("Allow AI sharing") { consent.allow() }.buttonStyle(.inkAction)
                    Button("Not now") { dismiss() }.tapTarget()
                }
            }
            .padding(Theme.Spacing.page)
        }
    }
}
