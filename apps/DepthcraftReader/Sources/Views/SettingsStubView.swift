import SwiftUI

struct SettingsStubView: View {
    @StateObject private var keyStore = APIKeyStore()
    @State private var showingKeyEntry: LLMProvider?
    @State private var keyInput = ""
    @State private var errorMessage: String?
    
    var body: some View {
        List {
            Section {
                Text("Configure API keys for course generation. Keys are stored securely in the device Keychain and never leave your device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Bring Your Own Key")
            }
            
            Section {
                providerRow(provider: .anthropic, hasKey: keyStore.hasAnthropicKey)
                providerRow(provider: .openai, hasKey: keyStore.hasOpenAIKey)
                providerRow(provider: .openrouter, hasKey: keyStore.hasOpenRouterKey)
            }
            
            Section("About") {
                LabeledContent("Reader", value: "0.1.0")
                LabeledContent("Schema", value: "0.1.0")
                LabeledContent("Mode", value: "Airplane / offline")
            }
        }
        .navigationTitle("Settings")
        .sheet(item: $showingKeyEntry) { provider in
            KeyEntrySheet(
                provider: provider,
                keyStore: keyStore,
                isPresented: Binding(
                    get: { showingKeyEntry != nil },
                    set: { if !$0 { showingKeyEntry = nil } }
                )
            )
        }
    }
    
    private func providerRow(provider: LLMProvider, hasKey: Bool) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(provider.displayName)
                if hasKey {
                    Text("Configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            if hasKey {
                Button("Remove", role: .destructive) {
                    try? keyStore.deleteKey(for: provider)
                }
                .buttonStyle(.borderless)
            } else {
                Button("Add Key") {
                    showingKeyEntry = provider
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

struct KeyEntrySheet: View {
    let provider: LLMProvider
    let keyStore: APIKeyStore
    @Binding var isPresented: Bool
    
    @State private var keyInput = ""
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("API Key", text: $keyInput)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("Your API key is stored securely in the device Keychain and never leaves your device.")
                        .font(.caption)
                }
            }
            .navigationTitle("Add \(provider.displayName) Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveKey()
                    }
                    .disabled(keyInput.isEmpty)
                }
            }
        }
    }
    
    private func saveKey() {
        do {
            try keyStore.setKey(keyInput, for: provider)
            isPresented = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension LLMProvider: Identifiable {
    var id: String { rawValue }
}
