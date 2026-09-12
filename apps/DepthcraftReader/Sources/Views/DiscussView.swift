import SwiftUI

struct DiscussView: View {
    let term: String
    let initialGloss: String
    let lessonContext: ExplainSheet.LessonContext
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: CourseStore
    @StateObject private var apiKeyStore = APIKeyStore()
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isGenerating = false
    @State private var error: String?
    
    private var glossService: GlossService {
        GlossService(apiKeyStore: apiKeyStore)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Chat messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            // System message explaining the context
                            ChatBubble(
                                role: .system,
                                content: "Ask follow-up questions about **\(term)** in the context of this lesson."
                            )
                            
                            // Show initial gloss as first assistant message
                            ChatBubble(
                                role: .assistant,
                                content: initialGloss
                            )
                            
                            // User messages
                            ForEach(messages) { message in
                                ChatBubble(role: message.role, content: message.content)
                                    .id(message.id)
                            }
                            
                            if isGenerating {
                                ChatBubble(role: .assistant, content: "Thinking...")
                                    .id("generating")
                            }
                            
                            if let error {
                                ErrorBubble(message: error)
                                    .id("error")
                            }
                        }
                        .padding()
                        .onChange(of: messages.count) { _ in
                            if let lastMessage = messages.last {
                                withAnimation {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                        .onChange(of: isGenerating) { generating in
                            if generating {
                                withAnimation {
                                    proxy.scrollTo("generating", anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                
                Divider()
                
                // Input bar
                HStack(spacing: 12) {
                    TextField("Ask a question...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                        .disabled(isGenerating || !glossService.hasAPIKey())
                    
                    Button {
                        Task {
                            await sendMessage()
                        }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.teal)
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating || !glossService.hasAPIKey())
                }
                .padding()
                .background(.bar)
                
                if !glossService.hasAPIKey() {
                    HStack(spacing: 8) {
                        Image(systemName: "key.slash")
                            .foregroundStyle(.orange)
                        Text("Add an API key in Settings → Generate to use Discuss")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle("Discuss: \(term)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func sendMessage() async {
        let userMessage = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userMessage.isEmpty else { return }
        
        // Add user message
        messages.append(ChatMessage(role: .user, content: userMessage))
        inputText = ""
        error = nil
        isGenerating = true
        
        do {
            // Build conversation context
            let conversationContext = buildConversationContext()
            
            // Get response from LLM
            guard let config = try getAvailableLLMConfig() else {
                throw GlossServiceError.noAPIKey
            }
            
            let client = try LLMClientFactory.createClient(config: config)
            
            let systemPrompt = """
            You are a helpful educational assistant discussing a lesson with a student.
            
            Original term: \(term)
            Original explanation: \(initialGloss)
            
            Lesson: \(lessonContext.lessonTitle) (from \(lessonContext.courseTitle))
            
            Answer the student's questions clearly and concisely, building on the original explanation.
            Keep responses short (3-4 sentences max). Use markdown for emphasis if helpful.
            """
            
            let response = try await client.complete(
                systemPrompt: systemPrompt,
                userPrompt: conversationContext + "\n\nStudent: \(userMessage)\n\nAssistant:",
                temperature: 0.7,
                maxTokens: 400
            )
            
            // Add assistant response
            messages.append(ChatMessage(role: .assistant, content: response.trimmingCharacters(in: .whitespacesAndNewlines)))
            
        } catch {
            self.error = error.localizedDescription
        }
        
        isGenerating = false
    }
    
    private func buildConversationContext() -> String {
        var context = "Previous conversation:\n\n"
        for message in messages {
            let prefix = message.role == .user ? "Student" : "Assistant"
            context += "\(prefix): \(message.content)\n\n"
        }
        return context
    }
    
    private func getAvailableLLMConfig() throws -> LLMConfiguration? {
        // Try Anthropic first
        if apiKeyStore.hasAnthropicKey, let key = try apiKeyStore.getKey(for: .anthropic) {
            return LLMConfiguration(
                provider: .anthropic,
                model: "claude-sonnet-4-20250514",
                apiKey: key,
                customBaseURL: nil
            )
        }
        
        // Try OpenAI
        if apiKeyStore.hasOpenAIKey, let key = try apiKeyStore.getKey(for: .openai) {
            return LLMConfiguration(
                provider: .openai,
                model: "gpt-4o",
                apiKey: key,
                customBaseURL: nil
            )
        }
        
        // Try OpenRouter
        if apiKeyStore.hasOpenRouterKey, let key = try apiKeyStore.getKey(for: .openrouter) {
            return LLMConfiguration(
                provider: .openrouter,
                model: "anthropic/claude-sonnet-4",
                apiKey: key,
                customBaseURL: nil
            )
        }
        
        // Try Custom
        if apiKeyStore.hasCustomKey,
           let key = try apiKeyStore.getKey(for: .custom),
           let baseURL = apiKeyStore.getCustomBaseURL(),
           let model = apiKeyStore.getCustomModel() {
            return LLMConfiguration(
                provider: .custom,
                model: model,
                apiKey: key,
                customBaseURL: baseURL
            )
        }
        
        return nil
    }
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    let content: String
}

enum ChatRole {
    case system
    case user
    case assistant
}

struct ChatBubble: View {
    let role: ChatRole
    let content: String
    
    var body: some View {
        HStack {
            if role == .user { Spacer(minLength: 40) }
            
            VStack(alignment: .leading, spacing: 4) {
                if role == .system {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.caption)
                        Text("System")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                }
                
                Text(parseMarkdown(content))
                    .font(.body)
                    .foregroundStyle(role == .system ? .secondary : .primary)
                    .textSelection(.enabled)
            }
            .padding(12)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            if role == .assistant || role == .system { Spacer(minLength: 40) }
        }
    }
    
    private var backgroundColor: Color {
        switch role {
        case .system:
            return Color(uiColor: .secondarySystemGroupedBackground)
        case .user:
            return Color.teal.opacity(0.15)
        case .assistant:
            return Color(uiColor: .systemBackground)
        }
    }
    
    private func parseMarkdown(_ text: String) -> AttributedString {
        do {
            return try AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        } catch {
            return AttributedString(text)
        }
    }
}

struct ErrorBubble: View {
    let message: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
