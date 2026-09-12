import SwiftUI

struct GenerationView: View {
    @StateObject private var orchestrator: GenerationOrchestrator
    @StateObject private var keyStore = APIKeyStore()
    @EnvironmentObject private var courseStore: CourseStore
    @Environment(\.dismiss) private var dismiss
    
    let extendFromCourse: LoadedCourse?
    
    @State private var topic = "AI harness design for educational systems"
    @State private var locale = "en-CA"
    
    @State private var knowledgeLevel: KnowledgeLevel = .some
    @State private var depthLevel: DepthLevel = .standard
    
    @State private var plannerProvider: LLMProvider = .anthropic
    @State private var plannerModel = "claude-sonnet-5"
    @State private var plannerTemperature = 0.7
    
    @State private var lessonProvider: LLMProvider = .anthropic
    @State private var lessonModel = "claude-sonnet-5"
    @State private var lessonTemperature = 0.7
    
    @State private var quizProvider: LLMProvider = .anthropic
    @State private var quizModel = "claude-sonnet-5"
    @State private var quizTemperature = 0.7
    
    @State private var demoProvider: LLMProvider = .anthropic
    @State private var demoModel = "claude-sonnet-5"
    @State private var demoTemperature = 0.7
    
    @State private var customBaseURL = ""
    @State private var customModel = ""
    
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showingOpenPackage = false
    @State private var lastFailedRequest: GenerationRequest?
    
    init(extendFromCourse: LoadedCourse? = nil) {
        self.extendFromCourse = extendFromCourse
        let store = APIKeyStore()
        _keyStore = StateObject(wrappedValue: store)
        _orchestrator = StateObject(wrappedValue: GenerationOrchestrator(keyStore: store))
    }
    
    var body: some View {
        Form {
            if orchestrator.progress.phase == .idle {
                setupSection
            } else if orchestrator.progress.phase == .awaitingApproval {
                approvalSection
            } else if orchestrator.progress.phase == .completed {
                completedSection
            } else if orchestrator.progress.phase == .failed {
                failedSection
            } else {
                progressSection
            }
        }
        .navigationTitle(extendFromCourse != nil ? "Extend Course" : "Generate Course")
        .alert("Error", isPresented: $showingError) {
            Button("OK") {
                errorMessage = nil
                showingError = false
            }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        .onChange(of: orchestrator.progress.error) { _, newError in
            // Only show alert for errors when NOT in failed phase
            // (failed phase has dedicated UI with Retry/Back buttons)
            if newError != nil && orchestrator.progress.phase != .failed {
                showingError = true
            }
        }
        .alert("Package Loaded", isPresented: $showingOpenPackage) {
            Button("OK") {
                showingOpenPackage = false
                dismiss()
            }
        } message: {
            Text("The generated course has been loaded. Tap OK to return to the course home.")
        }
        .onAppear {
            // Load custom endpoint config from keyStore
            customBaseURL = keyStore.customBaseURL
            customModel = keyStore.customModel
            
            // If extending, pre-populate from existing course and default to Brief
            if let course = extendFromCourse {
                topic = course.manifest.topic
                locale = course.manifest.locale
                depthLevel = .brief
            }
            
            // Auto-switch to first available provider if needed
            ensureValidProviderSelections()
        }
        .onChange(of: keyStore.hasAnthropicKey) { _, _ in ensureValidProviderSelections() }
        .onChange(of: keyStore.hasOpenAIKey) { _, _ in ensureValidProviderSelections() }
        .onChange(of: keyStore.hasOpenRouterKey) { _, _ in ensureValidProviderSelections() }
        .onChange(of: keyStore.hasCustomKey) { _, _ in ensureValidProviderSelections() }
        .onChange(of: keyStore.customBaseURL) { _, _ in ensureValidProviderSelections() }
        .onChange(of: keyStore.customModel) { _, _ in ensureValidProviderSelections() }
    }
    
    private var availableProviders: [LLMProvider] {
        var providers: [LLMProvider] = []
        
        if keyStore.hasAnthropicKey {
            providers.append(.anthropic)
        }
        if keyStore.hasOpenAIKey {
            providers.append(.openai)
        }
        if keyStore.hasOpenRouterKey {
            providers.append(.openrouter)
        }
        // Custom requires key + base URL + model
        if keyStore.hasCustomKey && !keyStore.customBaseURL.isEmpty && !keyStore.customModel.isEmpty {
            providers.append(.custom)
        }
        
        return providers
    }
    
    private var hasAnyProviderConfigured: Bool {
        !availableProviders.isEmpty
    }
    
    private func ensureValidProviderSelections() {
        guard hasAnyProviderConfigured else { return }
        
        let available = availableProviders
        
        // Auto-switch invalid selections to first available (prefer Anthropic)
        let preferredDefault = available.contains(.anthropic) ? .anthropic : available.first!
        
        if !available.contains(plannerProvider) {
            let oldProvider = plannerProvider
            plannerProvider = preferredDefault
            // Reset model to new provider's default when switching
            if oldProvider != plannerProvider {
                plannerModel = defaultModel(for: plannerProvider)
            }
        }
        if !available.contains(lessonProvider) {
            let oldProvider = lessonProvider
            lessonProvider = preferredDefault
            if oldProvider != lessonProvider {
                lessonModel = defaultModel(for: lessonProvider)
            }
        }
        if !available.contains(quizProvider) {
            let oldProvider = quizProvider
            quizProvider = preferredDefault
            if oldProvider != quizProvider {
                quizModel = defaultModel(for: quizProvider)
            }
        }
        if !available.contains(demoProvider) {
            let oldProvider = demoProvider
            demoProvider = preferredDefault
            if oldProvider != demoProvider {
                demoModel = defaultModel(for: demoProvider)
            }
        }
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
            return keyStore.customModel
        }
    }
    
    private var setupSection: some View {
        Group {
            Section("Course Topic") {
                TextField("Topic", text: $topic, axis: .vertical)
                    .lineLimit(2...4)
                
                Picker("Locale", selection: $locale) {
                    Text("English (Canada)").tag("en-CA")
                    Text("English (US)").tag("en-US")
                    Text("French").tag("fr-FR")
                }
            }
            
            Section("Planner") {
                roleConfiguration(
                    provider: $plannerProvider,
                    model: $plannerModel,
                    temperature: $plannerTemperature
                )
            }
            
            Section("Lesson Writer") {
                roleConfiguration(
                    provider: $lessonProvider,
                    model: $lessonModel,
                    temperature: $lessonTemperature
                )
            }
            
            Section("Quiz Writer") {
                roleConfiguration(
                    provider: $quizProvider,
                    model: $quizModel,
                    temperature: $quizTemperature
                )
            }
            
            Section {
                roleConfiguration(
                    provider: $demoProvider,
                    model: $demoModel,
                    temperature: $demoTemperature
                )
            } header: {
                Text("Demo Writer")
            } footer: {
                Text("Creates optional interactive demos. Most lessons will have zero demos. Density controlled by depth level.")
                    .font(.caption)
            }
            
            Section("Advanced") {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Current knowledge")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Picker("Current knowledge", selection: $knowledgeLevel) {
                                ForEach(KnowledgeLevel.allCases) { level in
                                    Text(level.displayName).tag(level)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            
                            Text("Higher levels skip/compress foundational content")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Desired depth")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Picker("Desired depth", selection: $depthLevel) {
                                ForEach(DepthLevel.allCases) { level in
                                    Text(level.displayName).tag(level)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            
                            Text("Higher levels produce longer, more comprehensive courses")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                } label: {
                    Text("Knowledge & Depth Controls")
                }
            }
            
            Section {
                if hasAnyProviderConfigured && canStartPlanning {
                    Text(costShapeCue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)
                }
                
                Button("Start Planning") {
                    startPlanning()
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .disabled(!canStartPlanning)
            } footer: {
                if !hasAnyProviderConfigured {
                    Text("Configure at least one API key in Settings to start generating courses.")
                        .foregroundStyle(.red)
                } else if !canStartPlanning {
                    Text("Configure API key for \(plannerProvider.displayName) in Settings")
                        .foregroundStyle(.red)
                }
            }
        }
    }
    
    private var approvalSection: some View {
        Group {
            if let curriculum = orchestrator.draftCurriculum {
                VStack {
                    Text("Curriculum planned. Tap below to edit and approve.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding()
                    
                    NavigationLink {
                        CurriculumEditorView(
                            curriculum: Binding(
                                get: { orchestrator.draftCurriculum ?? curriculum },
                                set: { orchestrator.draftCurriculum = $0 }
                            ),
                            onApprove: { selectedUnitIds in
                                continueGeneration(selectedUnitIds: selectedUnitIds)
                            },
                            onCancel: {
                                orchestrator.reset()
                            },
                            isDelta: extendFromCourse != nil
                        )
                    } label: {
                        Label("Edit & Approve Curriculum", systemImage: "pencil.circle")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                }
            }
        }
    }
    
    private var progressSection: some View {
        Section {
            VStack(spacing: 16) {
                Text(orchestrator.progress.phase.displayName)
                    .font(.headline)
                
                ProgressView(value: orchestrator.progress.progressPercent)
                
                if let item = orchestrator.progress.currentItem {
                    Text(item)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Text("\(orchestrator.progress.completedItems) of \(orchestrator.progress.totalItems)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical)
        }
    }
    
    private var completedSection: some View {
        Group {
            if let output = orchestrator.output {
                Section("Generation Complete") {
                    LabeledContent("Title", value: output.manifest.title)
                    LabeledContent("Units", value: "\(output.curriculum.units.count)")
                    LabeledContent("Lessons", value: "\(output.curriculum.lessons.count)")
                    
                    Text("Saved on this iPad")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Section {
                    Button {
                        openGeneratedPackage(output.packageURL)
                    } label: {
                        Label("Open in Reader", systemImage: "book.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                    
                    Button("Generate Another") {
                        orchestrator.reset()
                    }
                }
            }
        }
    }
    
    private var failedSection: some View {
        Group {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text("Generation Failed")
                            .font(.headline)
                    }
                    
                    if let error = orchestrator.progress.error {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
            
            Section {
                Button {
                    retryGeneration()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                
                Button("Back to Setup", role: .cancel) {
                    orchestrator.reset()
                }
            }
        }
    }
    
    private func roleConfiguration(provider: Binding<LLMProvider>, model: Binding<String>, temperature: Binding<Double>) -> some View {
        Group {
            Picker("Provider", selection: provider) {
                ForEach(availableProviders, id: \.self) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .onChange(of: provider.wrappedValue) { oldValue, newValue in
                // Reset model to provider's default when switching providers
                if oldValue != newValue {
                    model.wrappedValue = defaultModel(for: newValue)
                }
            }
            
            if provider.wrappedValue == .custom {
                TextField("Base URL", text: $customBaseURL)
                    .textContentType(.URL)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                
                TextField("Model", text: $customModel)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
            } else {
                TextField("Model", text: model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            
            HStack {
                Text("Temperature")
                Spacer()
                Text(String(format: "%.1f", temperature.wrappedValue))
                    .foregroundStyle(.secondary)
            }
            
            Slider(value: temperature, in: 0.0...2.0, step: 0.1)
                .tint(.teal)
        }
    }
    
    private var canStartPlanning: Bool {
        // Check if any providers configured
        guard hasAnyProviderConfigured else {
            return false
        }
        
        // Check for API key
        guard let key = try? keyStore.getKey(for: plannerProvider), key != nil else {
            return false
        }
        
        // If custom provider, also need base URL and model
        if plannerProvider == .custom {
            return !customBaseURL.isEmpty && !customModel.isEmpty
        }
        
        return true
    }
    
    private var costShapeCue: String {
        // Cost cue is mainly driven by depth, with knowledge providing slight nudges
        let baseDescriptor: String
        
        switch depthLevel {
        case .brief:
            baseDescriptor = "shorter"
        case .standard:
            baseDescriptor = "typical"
        case .deep:
            baseDescriptor = "longer"
        case .thorough:
            baseDescriptor = "longer"
        case .exhaustive:
            baseDescriptor = "longer"
        }
        
        // Knowledge can nudge the descriptor slightly
        let adjustedDescriptor: String
        if depthLevel == .standard {
            // At standard depth, knowledge has more influence
            if knowledgeLevel == .expert || knowledgeLevel == .strong {
                adjustedDescriptor = "shorter"
            } else if knowledgeLevel == .new {
                adjustedDescriptor = "longer"
            } else {
                adjustedDescriptor = baseDescriptor
            }
        } else {
            adjustedDescriptor = baseDescriptor
        }
        
        return "Expected generation: \(adjustedDescriptor)"
    }
    
    private var canContinueGeneration: Bool {
        // Check if lesson, quiz, and demo providers have keys
        guard let lessonKey = try? keyStore.getKey(for: lessonProvider), lessonKey != nil else {
            return false
        }
        guard let quizKey = try? keyStore.getKey(for: quizProvider), quizKey != nil else {
            return false
        }
        guard let demoKey = try? keyStore.getKey(for: demoProvider), demoKey != nil else {
            return false
        }
        
        // If custom providers, also need base URL and model
        if lessonProvider == .custom && (customBaseURL.isEmpty || customModel.isEmpty) {
            return false
        }
        if quizProvider == .custom && (customBaseURL.isEmpty || customModel.isEmpty) {
            return false
        }
        if demoProvider == .custom && (customBaseURL.isEmpty || customModel.isEmpty) {
            return false
        }
        
        return true
    }
    
    private func startPlanning() {
        do {
            let plannerKey = try keyStore.getKey(for: plannerProvider)
            guard let plannerKey else {
                errorMessage = "No API key configured for \(plannerProvider.displayName)"
                showingError = true
                return
            }
            
            // Validate custom endpoint config
            if plannerProvider == .custom {
                guard !customBaseURL.isEmpty else {
                    errorMessage = "Custom endpoint requires a base URL"
                    showingError = true
                    return
                }
                guard !customModel.isEmpty else {
                    errorMessage = "Custom endpoint requires a model"
                    showingError = true
                    return
                }
            }
            
            let effectiveModel = plannerProvider == .custom ? customModel : plannerModel
            let effectiveBaseURL = plannerProvider == .custom ? customBaseURL : nil
            
            let request = GenerationRequest(
                topic: topic,
                locale: locale,
                plannerConfig: LLMConfiguration(
                    provider: plannerProvider,
                    model: effectiveModel,
                    apiKey: plannerKey,
                    temperature: plannerTemperature,
                    customBaseURL: effectiveBaseURL
                ),
                lessonWriterConfig: LLMConfiguration(
                    provider: lessonProvider,
                    model: lessonModel,
                    apiKey: "",
                    temperature: lessonTemperature
                ),
                quizWriterConfig: LLMConfiguration(
                    provider: quizProvider,
                    model: quizModel,
                    apiKey: "",
                    temperature: quizTemperature
                ),
                demoWriterConfig: LLMConfiguration(
                    provider: demoProvider,
                    model: demoModel,
                    apiKey: "",
                    temperature: demoTemperature
                ),
                generateUnitIds: nil,
                knowledgeLevel: knowledgeLevel,
                depthLevel: depthLevel,
                extendFromPackageURL: extendFromCourse?.rootURL
            )
            
            lastFailedRequest = request
            
            Task {
                await orchestrator.startGeneration(request: request)
            }
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
    
    private func continueGeneration(selectedUnitIds: Set<String>) {
        do {
            // Validate all required keys present
            guard canContinueGeneration else {
                errorMessage = "Missing API keys for lesson writer or quiz writer. Please configure in Settings."
                showingError = true
                return
            }
            
            let lessonKey = try keyStore.getKey(for: lessonProvider)
            guard let lessonKey else {
                errorMessage = "No API key configured for \(lessonProvider.displayName)"
                showingError = true
                return
            }
            
            let quizKey = try keyStore.getKey(for: quizProvider)
            guard let quizKey else {
                errorMessage = "No API key configured for \(quizProvider.displayName)"
                showingError = true
                return
            }
            
            let demoKey = try keyStore.getKey(for: demoProvider)
            guard let demoKey else {
                errorMessage = "No API key configured for \(demoProvider.displayName)"
                showingError = true
                return
            }
            
            let plannerKey = try keyStore.getKey(for: plannerProvider)
            guard let plannerKey else {
                errorMessage = "No API key configured for \(plannerProvider.displayName)"
                showingError = true
                return
            }
            
            // Validate custom endpoints if used
            if lessonProvider == .custom && (customBaseURL.isEmpty || customModel.isEmpty) {
                errorMessage = "Custom endpoint for lesson writer requires base URL and model"
                showingError = true
                return
            }
            if quizProvider == .custom && (customBaseURL.isEmpty || customModel.isEmpty) {
                errorMessage = "Custom endpoint for quiz writer requires base URL and model"
                showingError = true
                return
            }
            if demoProvider == .custom && (customBaseURL.isEmpty || customModel.isEmpty) {
                errorMessage = "Custom endpoint for demo writer requires base URL and model"
                showingError = true
                return
            }
            if plannerProvider == .custom && (customBaseURL.isEmpty || customModel.isEmpty) {
                errorMessage = "Custom endpoint for planner requires base URL and model"
                showingError = true
                return
            }
            
            let plannerEffectiveModel = plannerProvider == .custom ? customModel : plannerModel
            let plannerEffectiveBaseURL = plannerProvider == .custom ? customBaseURL : nil
            
            let lessonEffectiveModel = lessonProvider == .custom ? customModel : lessonModel
            let lessonEffectiveBaseURL = lessonProvider == .custom ? customBaseURL : nil
            
            let quizEffectiveModel = quizProvider == .custom ? customModel : quizModel
            let quizEffectiveBaseURL = quizProvider == .custom ? customBaseURL : nil
            
            let demoEffectiveModel = demoProvider == .custom ? customModel : demoModel
            let demoEffectiveBaseURL = demoProvider == .custom ? customBaseURL : nil
            
            let request = GenerationRequest(
                topic: topic,
                locale: locale,
                plannerConfig: LLMConfiguration(
                    provider: plannerProvider,
                    model: plannerEffectiveModel,
                    apiKey: plannerKey,
                    temperature: plannerTemperature,
                    customBaseURL: plannerEffectiveBaseURL
                ),
                lessonWriterConfig: LLMConfiguration(
                    provider: lessonProvider,
                    model: lessonEffectiveModel,
                    apiKey: lessonKey,
                    temperature: lessonTemperature,
                    customBaseURL: lessonEffectiveBaseURL
                ),
                quizWriterConfig: LLMConfiguration(
                    provider: quizProvider,
                    model: quizEffectiveModel,
                    apiKey: quizKey,
                    temperature: quizTemperature,
                    customBaseURL: quizEffectiveBaseURL
                ),
                demoWriterConfig: LLMConfiguration(
                    provider: demoProvider,
                    model: demoEffectiveModel,
                    apiKey: demoKey,
                    temperature: demoTemperature,
                    customBaseURL: demoEffectiveBaseURL
                ),
                generateUnitIds: selectedUnitIds.isEmpty ? nil : Array(selectedUnitIds),
                knowledgeLevel: knowledgeLevel,
                depthLevel: depthLevel,
                extendFromPackageURL: extendFromCourse?.rootURL
            )
            
            lastFailedRequest = request
            
            Task {
                await orchestrator.continueGeneration(request: request)
            }
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
    
    private func retryGeneration() {
        guard let request = lastFailedRequest else {
            orchestrator.reset()
            return
        }
        
        Task {
            if orchestrator.draftCurriculum != nil {
                // Was in generation phase (post-approve)
                await orchestrator.continueGeneration(request: request)
            } else {
                // Was in planning phase
                await orchestrator.startGeneration(request: request)
            }
        }
    }
    
    private func openGeneratedPackage(_ url: URL) {
        courseStore.loadPackage(from: url)
        if courseStore.errorMessage == nil {
            showingOpenPackage = true
        } else {
            errorMessage = courseStore.errorMessage
            showingError = true
        }
    }
}
