import SwiftUI

struct GenerationView: View {
    @StateObject private var orchestrator: GenerationOrchestrator
    @StateObject private var keyStore = APIKeyStore()
    
    @State private var topic = "AI harness design for educational systems"
    @State private var locale = "en-CA"
    
    @State private var plannerProvider: LLMProvider = .anthropic
    @State private var plannerModel = "claude-3-5-sonnet-20241022"
    
    @State private var lessonProvider: LLMProvider = .anthropic
    @State private var lessonModel = "claude-3-5-sonnet-20241022"
    
    @State private var quizProvider: LLMProvider = .openai
    @State private var quizModel = "gpt-4o"
    
    @State private var errorAlert: String?
    
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
            } else {
                progressSection
            }
        }
        .navigationTitle("Generate Course")
        .alert("Error", isPresented: .constant(orchestrator.progress.error != nil)) {
            Button("OK") {
                orchestrator.reset()
            }
        } message: {
            if let error = orchestrator.progress.error {
                Text(error)
            }
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
                    Text("Configure at least one API key in Settings")
                        .foregroundStyle(.red)
                }
            }
        }
    }
    
    private var approvalSection: some View {
        Group {
            if let curriculum = orchestrator.draftCurriculum {
                Section("Draft Curriculum") {
                    Text("Review the planned curriculum and approve to continue generation.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    ForEach(curriculum.units) { unit in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(unit.title)
                                .font(.headline)
                            
                            ForEach(unit.lessonIds, id: \.self) { lessonId in
                                if let lesson = curriculum.lessons[lessonId] {
                                    HStack {
                                        Text("•")
                                        Text(lesson.title)
                                        Spacer()
                                        if let minutes = lesson.estimatedMinutes {
                                            Text("\(minutes) min")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .font(.subheadline)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Section {
                    Button("Approve & Generate") {
                        continueGeneration()
                    }
                    
                    Button("Cancel", role: .destructive) {
                        orchestrator.reset()
                    }
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
                    Button("Generate Another") {
                        orchestrator.reset()
                    }
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
        keyStore.hasAnthropicKey || keyStore.hasOpenAIKey || keyStore.hasOpenRouterKey
    }
    
    private func startPlanning() {
        do {
            let plannerKey = try keyStore.getKey(for: plannerProvider)
            guard let plannerKey else {
                errorAlert = "No API key configured for \(plannerProvider.displayName)"
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
            
            Task {
                await orchestrator.startGeneration(request: request)
            }
        } catch {
            errorAlert = error.localizedDescription
        }
    }
    
    private func continueGeneration() {
        do {
            let lessonKey = try keyStore.getKey(for: lessonProvider)
            guard let lessonKey else {
                errorAlert = "No API key configured for \(lessonProvider.displayName)"
                return
            }
            
            let quizKey = try keyStore.getKey(for: quizProvider)
            guard let quizKey else {
                errorAlert = "No API key configured for \(quizProvider.displayName)"
                return
            }
            
            let plannerKey = try keyStore.getKey(for: plannerProvider)
            guard let plannerKey else {
                errorAlert = "No API key configured for \(plannerProvider.displayName)"
                return
            }
            
            let request = GenerationRequest(
                topic: topic,
                locale: locale,
                plannerConfig: LLMConfiguration(provider: plannerProvider, model: plannerModel, apiKey: plannerKey),
                lessonWriterConfig: LLMConfiguration(provider: lessonProvider, model: lessonModel, apiKey: lessonKey),
                quizWriterConfig: LLMConfiguration(provider: quizProvider, model: quizModel, apiKey: quizKey),
                generateUnitIds: nil
            )
            
            Task {
                await orchestrator.continueGeneration(request: request)
            }
        } catch {
            errorAlert = error.localizedDescription
        }
    }
}
