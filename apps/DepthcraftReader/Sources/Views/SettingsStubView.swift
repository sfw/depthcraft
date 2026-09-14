import SwiftUI

struct SettingsStubView: View {
    @StateObject private var keyStore = APIKeyStore()
    @StateObject private var customEndpointsStore = CustomEndpointsStore()
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @State private var showingKeyEntry: LLMProvider?
    @State private var showingCustomEndpointSheet: CustomEndpointSheet.Mode?
    @State private var keyInput = ""
    @State private var errorMessage: String?
    
    var body: some View {
        List {
            Section("Generate") {
                NavigationLink {
                    GenerateSettingsView()
                } label: {
                    Label("Models", systemImage: "cpu")
                }
            }
            
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
                ForEach(customEndpointsStore.endpoints) { endpoint in
                    customEndpointRow(endpoint: endpoint)
                }
                
                Button {
                    showingCustomEndpointSheet = .add
                } label: {
                    Label("Add Custom Endpoint", systemImage: "plus.circle")
                }
            } header: {
                Text("Custom Endpoints (OpenAI-compatible)")
            } footer: {
                Text("Add multiple custom OpenAI-compatible endpoints such as Moonshot/Kimi (https://api.moonshot.cn/v1) or any other compatible API. Each endpoint appears as its own provider in model selection.")
                    .font(.caption)
            }
            
            Section("About") {
                LabeledContent("Reader", value: "0.1.0")
                LabeledContent("Schema", value: "0.1.0")
                LabeledContent("Mode", value: networkMonitor.isOnline ? "Online" : "Offline")
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            // Perform migration on first appearance
            customEndpointsStore.migrateLegacyCustomEndpoint(from: keyStore)
        }
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
        .sheet(item: $showingCustomEndpointSheet) { mode in
            CustomEndpointSheet(
                mode: mode,
                customEndpointsStore: customEndpointsStore,
                isPresented: Binding(
                    get: { showingCustomEndpointSheet != nil },
                    set: { if !$0 { showingCustomEndpointSheet = nil } }
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
    
    private func customEndpointRow(endpoint: CustomEndpoint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(endpoint.label)
                        .font(.body)
                    
                    if customEndpointsStore.hasKey(for: endpoint) {
                        Text("Configured")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text(endpoint.baseURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        
                        if let defaultModel = endpoint.defaultModel {
                            Text("Model: \(defaultModel)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No key configured")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                
                Spacer()
                
                Button("Edit") {
                    showingCustomEndpointSheet = .edit(endpoint)
                }
                .font(.caption)
                .buttonStyle(.bordered)
                
                Button("Remove", role: .destructive) {
                    customEndpointsStore.delete(endpoint)
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
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
    enum Mode: Identifiable {
        case add
        case edit(CustomEndpoint)
        
        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let endpoint): return "edit-\(endpoint.id.uuidString)"
            }
        }
    }
    
    let mode: Mode
    let customEndpointsStore: CustomEndpointsStore
    @Binding var isPresented: Bool
    
    @State private var label: String
    @State private var baseURL: String
    @State private var defaultModel: String
    @State private var apiKey: String
    @State private var hasExistingKey: Bool
    @State private var errorMessage: String?
    
    init(mode: Mode, customEndpointsStore: CustomEndpointsStore, isPresented: Binding<Bool>) {
        self.mode = mode
        self.customEndpointsStore = customEndpointsStore
        self._isPresented = isPresented
        
        switch mode {
        case .add:
            self._label = State(initialValue: "")
            self._baseURL = State(initialValue: "")
            self._defaultModel = State(initialValue: "")
            self._apiKey = State(initialValue: "")
            self._hasExistingKey = State(initialValue: false)
        case .edit(let endpoint):
            self._label = State(initialValue: endpoint.label)
            self._baseURL = State(initialValue: endpoint.baseURL)
            self._defaultModel = State(initialValue: endpoint.defaultModel ?? "")
            self._apiKey = State(initialValue: "")
            let hasKey = customEndpointsStore.hasKey(for: endpoint)
            self._hasExistingKey = State(initialValue: hasKey)
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Label", text: $label)
                        .autocorrectionDisabled()
                    
                    TextField("Base URL", text: $baseURL)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    
                    TextField("Default Model (optional)", text: $defaultModel)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    
                    SecureField(hasExistingKey ? "API Key (configured)" : "API Key", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                    
                    if hasExistingKey && apiKey.isEmpty {
                        Text("Leave blank to keep existing key, or enter new key to replace")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Endpoint Configuration")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Label: A friendly name for this endpoint (e.g., \"Moonshot\", \"Local LLM\")")
                        Text("Base URL: e.g., https://api.moonshot.cn/v1")
                        Text("Default Model: Optional. Will be used as initial model selection.")
                        Text("")
                        Text("Your API key is stored securely in the device Keychain and never leaves your device.")
                    }
                    .font(.caption)
                }
            }
            .navigationTitle(mode.isAdd ? "Add Custom Endpoint" : "Edit Custom Endpoint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveEndpoint()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
    
    private var isValid: Bool {
        !label.trimmingCharacters(in: .whitespaces).isEmpty &&
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        (hasExistingKey || !apiKey.isEmpty)
    }
    
    private func saveEndpoint() {
        do {
            let trimmedLabel = label.trimmingCharacters(in: .whitespaces)
            let trimmedURL = baseURL.trimmingCharacters(in: .whitespaces)
            let trimmedModel = defaultModel.trimmingCharacters(in: .whitespaces)
            
            switch mode {
            case .add:
                let endpoint = CustomEndpoint(
                    label: trimmedLabel,
                    baseURL: trimmedURL,
                    defaultModel: trimmedModel.isEmpty ? nil : trimmedModel
                )
                if !apiKey.isEmpty {
                    try customEndpointsStore.setKey(apiKey, for: endpoint)
                }
                customEndpointsStore.add(endpoint)
                
            case .edit(let existingEndpoint):
                let updatedEndpoint = CustomEndpoint(
                    id: existingEndpoint.id,
                    label: trimmedLabel,
                    baseURL: trimmedURL,
                    defaultModel: trimmedModel.isEmpty ? nil : trimmedModel
                )
                if !apiKey.isEmpty {
                    try customEndpointsStore.setKey(apiKey, for: updatedEndpoint)
                }
                customEndpointsStore.update(updatedEndpoint)
            }
            
            isPresented = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension CustomEndpointSheet.Mode {
    var isAdd: Bool {
        if case .add = self { return true }
        return false
    }
}

extension LLMProvider: Identifiable {
    var id: String { rawValue }
}
