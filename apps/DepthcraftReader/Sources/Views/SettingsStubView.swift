import SwiftUI

struct SettingsStubView: View {
    var body: some View {
        List {
            Section("Bring your own key") {
                Text("Generation (planner / lesson / quiz / packager) is out of scope for the v0.1 reader. This screen is a placeholder for future on-device BYOK settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                LabeledContent("Anthropic", value: "Not configured")
                LabeledContent("OpenAI", value: "Not configured")
                LabeledContent("OpenRouter", value: "Not configured")
            }
            Section("About") {
                LabeledContent("Reader", value: "0.1.0")
                LabeledContent("Schema", value: "0.1.0")
                LabeledContent("Mode", value: "Airplane / offline")
            }
        }
        .navigationTitle("Settings")
    }
}
