import SwiftUI

/// Settings section for configuring global LLM and per-role overrides
struct GenerateSettingsView: View {
    @StateObject private var apiKeyStore = APIKeyStore()
    @StateObject private var customEndpointsStore = CustomEndpointsStore()
    @StateObject private var roleConfig: LLMRoleConfigService
    @StateObject private var modelService: LLMModelService
    
    @State private var modelPickerTarget: ModelPickerTarget?
    @State private var roleCustomModelPicker: RoleCustomModelPicker?
    @State private var globalTemperature: Double?
    @State private var showTemperatureControl = false
    
    init() {
        let store = APIKeyStore()
        let customStore = CustomEndpointsStore()
        _apiKeyStore = StateObject(wrappedValue: store)
        _customEndpointsStore = StateObject(wrappedValue: customStore)
        _roleConfig = StateObject(wrappedValue: LLMRoleConfigService(apiKeyStore: store, customEndpointsStore: customStore))
        _modelService = StateObject(wrappedValue: LLMModelService(apiKeyStore: store, customEndpointsStore: customStore))
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
    
    struct RoleCustomModelPicker: Identifiable {
        let role: GenerationRole
        let selection: ProviderSelection
        let currentModel: String
        
        var id: String {
            switch selection {
            case .fixed(let provider):
                return "\(role.rawValue)-\(provider.rawValue)"
            case .customEndpoint(let endpointId):
                return "\(role.rawValue)-\(endpointId.uuidString)"
            }
        }
    }
    
    var body: some View {
        Form {
            globalSection
            rolesSection
        }
        .navigationTitle("Generate")
        .onAppear {
            globalTemperature = apiKeyStore.getGlobalTemperature()
            showTemperatureControl = globalTemperature != nil
            // Perform migration on first appearance
            customEndpointsStore.migrateLegacyCustomEndpoint(from: apiKeyStore)
        }
        .sheet(item: $modelPickerTarget) { target in
            modelPickerSheet(for: target)
        }
        .sheet(item: $roleCustomModelPicker) { picker in
            ProviderAwareModelPickerView(
                selection: picker.selection,
                currentModel: picker.currentModel,
                customEndpointsStore: customEndpointsStore
            ) { selectedModel in
                roleConfig.setRoleOverride(for: picker.role, selection: picker.selection, model: selectedModel)
            }
        }
    }
    
    private var globalSection: some View {
        Section {
            // Provider picker
            Picker("Provider", selection: Binding(
                get: { roleConfig.globalSelection },
                set: { newSelection in
                    if newSelection != roleConfig.globalSelection {
                        // Switch to default model for new provider
                        let defaultModel = defaultModel(for: newSelection)
                        roleConfig.setGlobalConfig(selection: newSelection, model: defaultModel)
                    }
                }
            )) {
                ForEach(availableSelections, id: \.self) { selection in
                    Text(displayName(for: selection)).tag(selection)
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
            
            // Temperature control
            if showTemperatureControl {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Temperature")
                        Spacer()
                        Text(String(format: "%.1f", globalTemperature ?? 1.0))
                            .foregroundStyle(.secondary)
                        Button {
                            withAnimation {
                                globalTemperature = nil
                                apiKeyStore.setGlobalTemperature(nil)
                                showTemperatureControl = false
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Slider(value: Binding(
                        get: { globalTemperature ?? 1.0 },
                        set: { newValue in
                            globalTemperature = newValue
                            apiKeyStore.setGlobalTemperature(newValue)
                        }
                    ), in: 0.0...2.0, step: 0.1)
                    .tint(.teal)
                }
            } else {
                Button {
                    withAnimation {
                        globalTemperature = 1.0
                        apiKeyStore.setGlobalTemperature(1.0)
                        showTemperatureControl = true
                    }
                } label: {
                    HStack {
                        Text("Temperature")
                        Spacer()
                        Text("Provider default")
                            .foregroundStyle(.secondary)
                        Image(systemName: "plus.circle")
                            .foregroundStyle(.teal)
                    }
                }
            }
        } header: {
            Text("Global Model")
        } footer: {
            Text("The default model for all generation roles. API keys are configured in Settings. Per-role customization below.\n\nTemperature controls randomness (0 = focused, 2 = creative). When unset, uses the provider's default (typically 1.0).")
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
                    Text("\(displayName(for: override.selection)): \(override.model)")
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
            ProviderAwareModelPickerView(
                selection: roleConfig.globalSelection,
                currentModel: roleConfig.globalModel,
                customEndpointsStore: customEndpointsStore
            ) { selectedModel in
                roleConfig.setGlobalConfig(selection: roleConfig.globalSelection, model: selectedModel)
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
                                Text("\(displayName(for: roleConfig.globalSelection)): \(roleConfig.globalModel)")
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
                        let currentSelection = override?.selection ?? roleConfig.globalSelection
                        
                        Picker("Provider", selection: Binding(
                            get: { currentSelection },
                            set: { newSelection in
                                let defaultModel = self.defaultModel(for: newSelection)
                                roleConfig.setRoleOverride(for: role, selection: newSelection, model: defaultModel)
                            }
                        )) {
                            ForEach(availableSelections, id: \.self) { selection in
                                Text(displayName(for: selection)).tag(selection)
                            }
                        }
                    }
                    
                    Button {
                        // Get current config for the role
                        let override = roleConfig.getRoleOverride(for: role)
                        let currentSelection = override?.selection ?? roleConfig.globalSelection
                        let currentModel = override?.model ?? roleConfig.globalModel
                        
                        // Dismiss this sheet and show model picker
                        modelPickerTarget = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            roleCustomModelPicker = RoleCustomModelPicker(
                                role: role,
                                selection: currentSelection,
                                currentModel: currentModel
                            )
                        }
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
                        Text("Currently: \(displayName(for: override.selection)) / \(override.model)")
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
    
    private var availableSelections: [ProviderSelection] {
        var selections: [ProviderSelection] = []
        
        if apiKeyStore.hasAnthropicKey {
            selections.append(.fixed(.anthropic))
        }
        if apiKeyStore.hasOpenAIKey {
            selections.append(.fixed(.openai))
        }
        if apiKeyStore.hasOpenRouterKey {
            selections.append(.fixed(.openrouter))
        }
        
        // Add custom endpoints with keys
        for endpoint in customEndpointsStore.endpoints {
            if customEndpointsStore.hasKey(for: endpoint) {
                selections.append(.customEndpoint(endpoint.id))
            }
        }
        
        return selections
    }
    
    private func displayName(for selection: ProviderSelection) -> String {
        switch selection {
        case .fixed(let provider):
            return provider.displayName
        case .customEndpoint(let endpointId):
            if let endpoint = customEndpointsStore.getEndpoint(id: endpointId) {
                return endpoint.displayName
            }
            return "Custom Endpoint"
        }
    }
    
    private func defaultModel(for selection: ProviderSelection) -> String {
        switch selection {
        case .fixed(let provider):
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
        case .customEndpoint(let endpointId):
            if let endpoint = customEndpointsStore.getEndpoint(id: endpointId),
               let defaultModel = endpoint.defaultModel {
                return defaultModel
            }
            return ""
        }
    }
}
