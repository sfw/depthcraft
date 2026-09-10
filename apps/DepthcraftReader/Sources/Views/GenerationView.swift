import SwiftUI

struct GenerationView: View {
    @StateObject private var orchestrator: GenerationOrchestrator
    @StateObject private var keyStore = APIKeyStore()
    @EnvironmentObject private var courseStore: CourseStore
    
    @State private var topic = "AI harness design for educational systems"
    @State private var locale = "en-CA"
    
    @State private var plannerProvider: LLMProvider = .anthropic
    @State private var plannerModel = "claude-3-5-sonnet-20241022"
    
    @State private var lessonProvider: LLMProvider = .anthropic
    @State private var lessonModel = "claude-3-5-sonnet-20241022"
    
    @State private var quizProvider: LLMProvider = .openai
    @State private var quizModel = "gpt-4o"
    
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showingOpenPackage = false
    @State private var lastFailedRequest: GenerationRequest?
    
    init() {
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
        .navigationTitle("Generate Course")
        .alert("Error", isPresented: $showingError) {
            Button("OK") {
                errorMessage = nil
                showingError = false
            }
        } message: {
            if let error = orchestrator.progress.error {
                Text(error)
            } else if let error = errorMessage {
                Text(error)
            }
        }
        .onChange(of: orchestrator.progress.error) { _, newError in
            if newError != nil {
                showingError = true
            }
        }
        .alert("Package Loaded", isPresented: $showingOpenPackage) {
            Button("OK") {
                showingOpenPackage = false
            }
        } message: {
            Text("The generated course has been loaded into the reader. Tap OK to return to the course home.")
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
                providerPicker(provider: $plannerProvider, model: $plannerModel)
            }
            
            Section("Lesson Writer") {
                providerPicker(provider: $lessonProvider, model: $lessonModel)
            }
            
            Section("Quiz Writer") {
                providerPicker(provider: $quizProvider, model: $quizModel)
            }
            
            Section {
                Button("Start Planning") {
                    startPlanning()
                }
                .disabled(!canStartPlanning)
            } footer: {
                if !canStartPlanning {
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
                            }
                        )
                    } label: {
                        Label("Edit & Approve Curriculum", systemImage: "pencil.circle")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
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
                    LabeledContent("Package", value: output.manifest.packageId)
                    LabeledContent("Title", value: output.manifest.title)
                    LabeledContent("Units", value: "\(output.curriculum.units.count)")
                    LabeledContent("Lessons", value: "\(output.curriculum.lessons.count)")
                    
                    Text("Package saved to Documents folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(output.packageURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                
                Section {
                    Button {
                        openGeneratedPackage(output.packageURL)
                    } label: {
                        Label("Open in Reader", systemImage: "book.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    
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
                
                Button("Back to Setup", role: .cancel) {
                    orchestrator.reset()
                }
            }
        }
    }
    
    private func providerPicker(provider: Binding<LLMProvider>, model: Binding<String>) -> some View {
        Group {
            Picker("Provider", selection: provider) {
                ForEach(LLMProvider.allCases, id: \.self) { p in
                    Text(p.displayName).tag(p)
                }
            }
            
            TextField("Model", text: model)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }
    
    private var canStartPlanning: Bool {
        guard let key = try? keyStore.getKey(for: plannerProvider), key != nil else {
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
            
            let request = GenerationRequest(
                topic: topic,
                locale: locale,
                plannerConfig: LLMConfiguration(provider: plannerProvider, model: plannerModel, apiKey: plannerKey),
                lessonWriterConfig: LLMConfiguration(provider: lessonProvider, model: lessonModel, apiKey: ""),
                quizWriterConfig: LLMConfiguration(provider: quizProvider, model: quizModel, apiKey: ""),
                generateUnitIds: nil
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
            
            let plannerKey = try keyStore.getKey(for: plannerProvider)
            guard let plannerKey else {
                errorMessage = "No API key configured for \(plannerProvider.displayName)"
                showingError = true
                return
            }
            
            let request = GenerationRequest(
                topic: topic,
                locale: locale,
                plannerConfig: LLMConfiguration(provider: plannerProvider, model: plannerModel, apiKey: plannerKey),
                lessonWriterConfig: LLMConfiguration(provider: lessonProvider, model: lessonModel, apiKey: lessonKey),
                quizWriterConfig: LLMConfiguration(provider: quizProvider, model: quizModel, apiKey: quizKey),
                generateUnitIds: selectedUnitIds.isEmpty ? nil : Array(selectedUnitIds)
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
        showingOpenPackage = true
    }
}
