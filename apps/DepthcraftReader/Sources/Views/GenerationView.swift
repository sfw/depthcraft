import SwiftUI

struct GenerationView: View {
    @StateObject private var orchestrator: GenerationOrchestrator
    @StateObject private var keyStore = APIKeyStore()
    @StateObject private var roleConfig: LLMRoleConfigService
    @EnvironmentObject private var courseStore: CourseStore
    @Environment(\.dismiss) private var dismiss
    
    let extendFromCourse: LoadedCourse?
    
    @State private var topic = "AI harness design for educational systems"
    @State private var locale = "en-CA"
    
    @State private var knowledgeLevel: KnowledgeLevel = .some
    @State private var depthLevel: DepthLevel = .standard
    
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showingOpenPackage = false
    @State private var lastFailedRequest: GenerationRequest?
    
    init(extendFromCourse: LoadedCourse? = nil) {
        self.extendFromCourse = extendFromCourse
        let store = APIKeyStore()
        _keyStore = StateObject(wrappedValue: store)
        _orchestrator = StateObject(wrappedValue: GenerationOrchestrator(keyStore: store))
        _roleConfig = StateObject(wrappedValue: LLMRoleConfigService(apiKeyStore: store))
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
            // If extending, pre-populate from existing course and default to Brief
            if let course = extendFromCourse {
                topic = course.manifest.topic
                locale = course.manifest.locale
                depthLevel = .brief
            }
        }
    }
    
    private var hasAnyProviderConfigured: Bool {
        keyStore.hasAnthropicKey || keyStore.hasOpenAIKey || 
        keyStore.hasOpenRouterKey || keyStore.hasCustomKey
    }
    
    private var canStartPlanning: Bool {
        // Check if any providers configured
        guard hasAnyProviderConfigured else {
            return false
        }
        
        // Check if planner role has valid config
        do {
            let _ = try roleConfig.getLLMConfig(for: .planner)
            return true
        } catch {
            return false
        }
    }
    
    private var setupSection: some View {
        Group {
            Section {
                VStack(alignment: .leading, spacing: 20) {
                    TextField("Topic", text: $topic, axis: .vertical)
                        .lineLimit(2...4)
                        .font(.body)
                    
                    Text("Uses your API key · runs on-device after")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    Button("Start Planning") {
                        startPlanning()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                    .disabled(!canStartPlanning)
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 12)
            } footer: {
                if !hasAnyProviderConfigured {
                    Text("Open Settings to configure an API key")
                        .foregroundStyle(.red)
                } else if !canStartPlanning {
                    Text("Open Settings → Generate to configure models")
                        .foregroundStyle(.red)
                }
            }
            
            Section {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 24) {
                        Picker("Locale", selection: $locale) {
                            Text("English (Canada)").tag("en-CA")
                            Text("English (US)").tag("en-US")
                            Text("French").tag("fr-FR")
                        }
                        .pickerStyle(.menu)
                        
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
                            
                            Text("Higher levels skip foundational content")
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
                            
                            Text("Higher levels produce longer courses")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        if hasAnyProviderConfigured && canStartPlanning {
                            Text(costShapeCue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .padding(.vertical, 8)
                } label: {
                    Text("Advanced")
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
            VStack(alignment: .leading, spacing: 12) {
                progressStep(
                    label: "Curriculum",
                    isActive: orchestrator.progress.phase == .planning,
                    isCompleted: orchestrator.progress.phase.order > GenerationPhase.planning.order
                )
                
                progressStep(
                    label: "Lessons",
                    isActive: orchestrator.progress.phase == .writingLessons,
                    isCompleted: orchestrator.progress.phase.order > GenerationPhase.writingLessons.order
                )
                
                progressStep(
                    label: "Quizzes",
                    isActive: orchestrator.progress.phase == .writingQuizzes,
                    isCompleted: orchestrator.progress.phase.order > GenerationPhase.writingQuizzes.order
                )
                
                progressStep(
                    label: "Demos",
                    isActive: orchestrator.progress.phase == .writingDemos,
                    isCompleted: orchestrator.progress.phase.order > GenerationPhase.writingDemos.order
                )
                
                progressStep(
                    label: "Package",
                    isActive: orchestrator.progress.phase == .packaging,
                    isCompleted: orchestrator.progress.phase == .completed
                )
                
                if let item = orchestrator.progress.currentItem, orchestrator.progress.phase != .idle {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            
                            Text("\(orchestrator.progress.completedItems) of \(orchestrator.progress.totalItems)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    } label: {
                        Text("Details")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private func progressStep(label: String, isActive: Bool, isCompleted: Bool) -> some View {
        HStack(spacing: 12) {
            if isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            } else if isActive {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
            
            Text(label)
                .font(.caption2)
                .foregroundStyle(isActive ? .teal : .secondary)
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
        // Check if all role configs are valid
        do {
            let _ = try roleConfig.getLLMConfig(for: .lessons)
            let _ = try roleConfig.getLLMConfig(for: .quizzes)
            let _ = try roleConfig.getLLMConfig(for: .demos)
            return true
        } catch {
            return false
        }
    }
    
    private func startPlanning() {
        do {
            let plannerConfig = try roleConfig.getLLMConfig(for: .planner)
            
            // Lesson/quiz/demo configs will be set later during continueGeneration
            // For now, use empty placeholders
            let dummyConfig = LLMConfiguration(
                provider: roleConfig.globalProvider,
                model: roleConfig.globalModel,
                apiKey: "",
                temperature: 0.7
            )
            
            let request = GenerationRequest(
                topic: topic,
                locale: locale,
                plannerConfig: plannerConfig,
                lessonWriterConfig: dummyConfig,
                quizWriterConfig: dummyConfig,
                demoWriterConfig: dummyConfig,
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
            // Validate all required configs present
            guard canContinueGeneration else {
                errorMessage = "Some API keys or models are missing. Open Settings → Generate to configure"
                showingError = true
                return
            }
            
            let plannerConfig = try roleConfig.getLLMConfig(for: .planner)
            let lessonConfig = try roleConfig.getLLMConfig(for: .lessons)
            let quizConfig = try roleConfig.getLLMConfig(for: .quizzes)
            let demoConfig = try roleConfig.getLLMConfig(for: .demos)
            
            let request = GenerationRequest(
                topic: topic,
                locale: locale,
                plannerConfig: plannerConfig,
                lessonWriterConfig: lessonConfig,
                quizWriterConfig: quizConfig,
                demoWriterConfig: demoConfig,
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
            // CRITICAL: Don't show "Package Loaded" alert when upgrade dialog pending.
            // Otherwise "Package Loaded" races "Course Updated" and blocks it (first-Open flake).
            // After user taps Cancel/Apply, showUpgradeDialog clears and dismiss() handles nav.
            if !courseStore.showUpgradeDialog {
                showingOpenPackage = true
            }
        } else {
            errorMessage = courseStore.errorMessage
            showingError = true
        }
    }
}
