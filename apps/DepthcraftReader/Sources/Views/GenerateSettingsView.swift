import SwiftUI

/// Settings section for configuring global LLM and per-role overrides
struct GenerateSettingsView: View {
    @StateObject private var apiKeyStore = APIKeyStore()
    @StateObject private var roleConfig: LLMRoleConfigService
    @StateObject private var modelService: LLMModelService
    
    @State private var showingModelPicker = false
    @State private var modelPickerTarget: ModelPickerTarget?
    
    init() {
        let store = APIKeyStore()
        _apiKeyStore = StateObject(wrappedValue: store)
        _roleConfig = StateObject(wrappedValue: LLMRoleConfigService(apiKeyStore: store))
        _modelService = StateObject(wrappedValue: LLMModelService(apiKeyStore: store))
    }
    
    enum ModelPickerTarget: Identifiable {
        case global
        case role(GenerationRole)
        
        var id: String {
            switch self {
            case .global: return "global"
            case .role(let role): return role.rawValue
            }
        }
    }
    
    var body: some View {
        Form {
            globalSection
            rolesSection
        }
        .navigationTitle("Generate")
        .sheet(item: $modelPickerTarget) { target in
            modelPickerSheet(for: target)
        }
    }
    
    private var globalSection: some View {
        Section {
            // Provider picker
            Picker("Provider", selection: $roleConfig.globalProvider) {
                ForEach(availableProviders, id: \.self) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .onChange(of: roleConfig.globalProvider) { oldValue, newValue in
                if oldValue != newValue {
                    // Switch to default model for new provider
                    let defaultModel = defaultModel(for: newValue)
                    roleConfig.setGlobalConfig(provider: newValue, model: defaultModel)
                }
            }
            
            // Model display + picker button
            HStack {
                Text("Model")
                Spacer()
                Button {
                    modelPickerTarget = .global
                } label: {
                    HStack(spacing: 4) {
                        Text(roleConfig.globalModel)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        } header: {
            Text("Global Model")
        } footer: {
            Text("The default model for all generation roles. API keys are configured in Settings. Per-role customization below.")
                .font(.caption)
        }
    }
    
    private var rolesSection: some View {
        Section {
            ForEach(GenerationRole.allCases) { role in
                roleRow(for: role)
            }
        } header: {
            Text("Per-Role Configuration")
        } footer: {
            Text("Roles follow the global model by default. Customize a role to use a different model.")
                .font(.caption)
        }
    }
    
    private func roleRow(for role: GenerationRole) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(role.displayName)
                    .font(.body)
                
                if roleConfig.isFollowingGlobal(role: role) {
                    Text("Follow global")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let override = roleConfig.getRoleOverride(for: role) {
                    Text("\(override.provider.displayName): \(override.model)")
                        .font(.caption)
                        .foregroundStyle(.teal)
                }
            }
            
            Spacer()
            
            if !roleConfig.isFollowingGlobal(role: role) {
                Button("Reset") {
                    roleConfig.resetToGlobal(role: role)
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .tint(.secondary)
            }
            
            Button {
                modelPickerTarget = .role(role)
            } label: {
                if roleConfig.isFollowingGlobal(role: role) {
                    Image(systemName: "ellipsis.circle")
                } else {
                    Image(systemName: "pencil.circle.fill")
                }
            }
            .foregroundStyle(.teal)
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private func modelPickerSheet(for target: ModelPickerTarget) -> some View {
        switch target {
        case .global:
            ModelPickerView(
                provider: roleConfig.globalProvider,
                currentModel: roleConfig.globalModel
            ) { selectedModel in
                roleConfig.setGlobalConfig(provider: roleConfig.globalProvider, model: selectedModel)
            }
            
        case .role(let role):
            roleModelPicker(for: role)
        }
    }
    
    private func roleModelPicker(for role: GenerationRole) -> some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        roleConfig.resetToGlobal(role: role)
                        modelPickerTarget = nil
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Follow global")
                                    .foregroundStyle(.primary)
                                Text("\(roleConfig.globalProvider.displayName): \(roleConfig.globalModel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            if roleConfig.isFollowingGlobal(role: role) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.teal)
                            }
                        }
                    }
                } header: {
                    Text("Default")
                }
                
                Section {
                    // Provider picker for custom
                    if !roleConfig.isFollowingGlobal(role: role) {
                        let override = roleConfig.getRoleOverride(for: role)
                        let currentProvider = override?.provider ?? roleConfig.globalProvider
                        
                        Picker("Provider", selection: Binding(
                            get: { currentProvider },
                            set: { newProvider in
                                let defaultModel = self.defaultModel(for: newProvider)
                                roleConfig.setRoleOverride(for: role, provider: newProvider, model: defaultModel)
                            }
                        )) {
                            ForEach(availableProviders, id: \.self) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                    }
                    
                    Button {
                        let currentConfig = roleConfig.getRoleOverride(for: role) ?? (roleConfig.globalProvider, roleConfig.globalModel)
                        
                        // Show model picker for the provider
                        showProviderModelPicker(role: role, provider: currentConfig.provider, currentModel: currentConfig.model)
                    } label: {
                        HStack {
                            Text("Select custom model")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                } header: {
                    Text("Custom")
                } footer: {
                    if let override = roleConfig.getRoleOverride(for: role) {
                        Text("Currently: \(override.provider.displayName) / \(override.model)")
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(role.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        modelPickerTarget = nil
                    }
                }
            }
        }
    }
    
    private func showProviderModelPicker(role: GenerationRole, provider: LLMProvider, currentModel: String) {
        // This will be shown as a sheet within the role picker
        // For simplicity, we'll inline the model picker here
        // In a more complex app, we'd navigate or show another sheet
        
        // For now, we'll use the same pattern but need to handle the nested navigation
        // Let's simplify: selecting "Select custom model" dismisses and shows the model picker
        modelPickerTarget = nil
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Show custom model picker as a separate sheet
            // This is a workaround for nested sheets
            // In the actual implementation, we'd need to restructure this
            roleConfig.setRoleOverride(for: role, provider: provider, model: currentModel)
        }
    }
    
    private var availableProviders: [LLMProvider] {
        var providers: [LLMProvider] = []
        
        if apiKeyStore.hasAnthropicKey {
            providers.append(.anthropic)
        }
        if apiKeyStore.hasOpenAIKey {
            providers.append(.openai)
        }
        if apiKeyStore.hasOpenRouterKey {
            providers.append(.openrouter)
        }
        if apiKeyStore.hasCustomKey && !apiKeyStore.customBaseURL.isEmpty {
            providers.append(.custom)
        }
        
        return providers
    }
    
    private func defaultModel(for provider: LLMProvider) -> String {
        switch provider {
        case .anthropic:
            return "claude-sonnet-5"
        case .openai:
            return "gpt-4o"
        case .openrouter:
            return "anthropic/claude-sonnet-5"
        case .custom:
            return apiKeyStore.customModel
        }
    }
}
