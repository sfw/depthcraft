import SwiftUI

struct SettingsStubView: View {
    @StateObject private var keyStore = APIKeyStore()
    @State private var showingKeyEntry: LLMProvider?
    @State private var showingCustomConfig = false
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
            
            Section {
                customProviderRow()
            } header: {
                Text("Custom Endpoint (OpenAI-compatible)")
            } footer: {
                Text("Configure a custom OpenAI-compatible endpoint such as Moonshot/Kimi (https://api.moonshot.cn/v1) or any other compatible API.")
                    .font(.caption)
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
        .sheet(isPresented: $showingCustomConfig) {
            CustomEndpointSheet(
                keyStore: keyStore,
                isPresented: $showingCustomConfig
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
    
    private func customProviderRow() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Custom Endpoint")
                    .font(.body)
                
                Spacer()
                
                if keyStore.hasCustomKey && !keyStore.customBaseURL.isEmpty {
                    Button("Edit") {
                        showingCustomConfig = true
                    }
                    .buttonStyle(.borderless)
                    
                    Button("Remove", role: .destructive) {
                        try? keyStore.deleteKey(for: .custom)
                        keyStore.setCustomBaseURL("")
                        keyStore.setCustomModel("")
                    }
                    .buttonStyle(.borderless)
                } else {
                    Button("Configure") {
                        showingCustomConfig = true
                    }
                    .buttonStyle(.borderless)
                }
            }
            
            if keyStore.hasCustomKey && !keyStore.customBaseURL.isEmpty {
                Text("Configured")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if !keyStore.customBaseURL.isEmpty {
                    Text(keyStore.customBaseURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                if !keyStore.customModel.isEmpty {
                    Text("Model: \(keyStore.customModel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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

struct CustomEndpointSheet: View {
    let keyStore: APIKeyStore
    @Binding var isPresented: Bool
    
    @State private var baseURL: String
    @State private var model: String
    @State private var apiKey: String
    @State private var errorMessage: String?
    
    init(keyStore: APIKeyStore, isPresented: Binding<Bool>) {
        self.keyStore = keyStore
        self._isPresented = isPresented
        self._baseURL = State(initialValue: keyStore.customBaseURL)
        self._model = State(initialValue: keyStore.customModel)
        // Load existing key if present
        if let existingKey = try? keyStore.getKey(for: .custom) {
            self._apiKey = State(initialValue: existingKey)
        } else {
            self._apiKey = State(initialValue: "")
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Base URL", text: $baseURL)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    
                    TextField("Model", text: $model)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    
                    SecureField("API Key", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Endpoint Configuration")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Example for Moonshot/Kimi:")
                        Text("Base URL: https://api.moonshot.cn/v1")
                        Text("Model: moonshot-v1-8k")
                        Text("")
                        Text("Your API key is stored securely in the device Keychain and never leaves your device.")
                    }
                    .font(.caption)
                }
            }
            .navigationTitle("Custom Endpoint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveConfig()
                    }
                    .disabled(baseURL.isEmpty || model.isEmpty || apiKey.isEmpty)
                }
            }
        }
    }
    
    private func saveConfig() {
        do {
            try keyStore.setKey(apiKey, for: .custom)
            keyStore.setCustomBaseURL(baseURL)
            keyStore.setCustomModel(model)
            isPresented = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension LLMProvider: Identifiable {
    var id: String { rawValue }
}
