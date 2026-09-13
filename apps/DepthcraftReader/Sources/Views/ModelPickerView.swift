import SwiftUI

/// Filterable model picker that fetches models from provider APIs
struct ModelPickerView: View {
    let provider: LLMProvider
    let currentModel: String
    let onSelect: (String) -> Void
    
    @StateObject private var apiKeyStore = APIKeyStore()
    @StateObject private var modelService: LLMModelService
    
    @State private var models: [LLMModelService.ModelInfo] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var searchText = ""
    @State private var customModelInput = ""
    @State private var showingCustomInput = false
    
    @Environment(\.dismiss) private var dismiss
    
    init(provider: LLMProvider, currentModel: String, onSelect: @escaping (String) -> Void) {
        self.provider = provider
        self.currentModel = currentModel
        self.onSelect = onSelect
        
        let store = APIKeyStore()
        _apiKeyStore = StateObject(wrappedValue: store)
        _modelService = StateObject(wrappedValue: LLMModelService(apiKeyStore: store))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    ProgressView("Loading models...")
                        .padding()
                } else if let error = error {
                    errorView(error: error)
                } else {
                    modelListView
                }
            }
            .navigationTitle("Select Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Custom…") {
                        showingCustomInput = true
                    }
                    .font(.subheadline)
                }
            }
            .searchable(text: $searchText, prompt: "Filter models")
            .sheet(isPresented: $showingCustomInput) {
                customModelSheet
            }
            .task {
                await loadModels()
            }
        }
    }
    
    private var modelListView: some View {
        List {
            if filteredModels.isEmpty && !searchText.isEmpty {
                Section {
                    Text("No models match '\(searchText)'")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(filteredModels) { model in
                        Button {
                            onSelect(model.id)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.displayName)
                                        .foregroundStyle(.primary)
                                    if model.name != model.displayName {
                                        Text(model.name)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                if model.id == currentModel {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.teal)
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    private func errorView(error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            
            Text("Could not load models")
                .font(.headline)
            
            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Retry") {
                Task {
                    await loadModels()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)
            
            Button("Enter Custom Model ID") {
                showingCustomInput = true
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
    
    private var customModelSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Model ID", text: $customModelInput)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                } header: {
                    Text("Custom Model ID")
                } footer: {
                    Text("Enter the exact model identifier. Use this when the model isn't in the fetched list or when the fetch failed.")
                        .font(.caption)
                }
            }
            .navigationTitle("Custom Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingCustomInput = false
                        customModelInput = ""
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") {
                        onSelect(customModelInput)
                        showingCustomInput = false
                        dismiss()
                    }
                    .disabled(customModelInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
    
    private var filteredModels: [LLMModelService.ModelInfo] {
        if searchText.isEmpty {
            return models
        }
        let query = searchText.lowercased()
        return models.filter {
            $0.name.lowercased().contains(query) ||
            $0.displayName.lowercased().contains(query)
        }
    }
    
    private func loadModels() async {
        isLoading = true
        error = nil
        
        do {
            models = try await modelService.fetchModels(for: provider)
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
}
