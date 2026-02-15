#if canImport(FoundationModels)
import SwiftUI
import FoundationModels

@available(iOS 26, *)
struct ChatView: View {
    @Environment(APIService.self) private var apiService
    @State private var chatService = ChatService()
    @State private var inputText = ""
    @State private var speechService = SpeechRecognitionService()
    @State private var copiedHitId: String?
    @FocusState private var isInputFocused: Bool

    private let suggestionChips = [
        "Plan a ski trip with friends",
        "What agents are available?",
        "What sensors does Robo support?",
        "How do I scan a room?"
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    if chatService.messages.isEmpty {
                        emptyState
                    } else {
                        messageList
                    }
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: chatService.messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: chatService.currentStreamingText) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .safeAreaInset(edge: .bottom) {
                    inputBar
                }
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !chatService.messages.isEmpty {
                        Button {
                            chatService.resetSession()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                    }
                }
            }
            .onAppear {
                chatService.configure(apiService: apiService)
                chatService.prewarm()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()
                .frame(height: 60)

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Ask me anything about Robo")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("On-device AI \u{2022} Conversations stay private")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                ForEach(suggestionChips, id: \.self) { chip in
                    Button {
                        sendMessage(chip)
                    } label: {
                        Text(chip)
                            .font(.subheadline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding()
    }

    // MARK: - Message List

    private var messageList: some View {
        LazyVStack(spacing: 12) {
            ForEach(chatService.messages) { message in
                VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                    MessageBubble(
                        message: message,
                        isStreaming: chatService.isStreaming && message.id == chatService.messages.last?.id && message.role == .assistant
                    )

                    // Show copy-link buttons for HIT results
                    if let results = chatService.hitResults[message.id] {
                        HitResultButtons(results: results, copiedHitId: $copiedHitId)
                    }
                }
                .id(message.id)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            // Mic button
            Button {
                speechService.toggleRecording()
            } label: {
                Image(systemName: speechService.isRecording ? "mic.fill" : "mic")
                    .font(.title3)
                    .foregroundStyle(speechService.isRecording ? .red : .secondary)
                    .symbolEffect(.pulse, isActive: speechService.isRecording)
            }

            TextField("Message...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .padding(10)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 20))
                .onSubmit {
                    if !chatService.isStreaming && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        sendMessage(inputText)
                    }
                }

            Button {
                if chatService.isStreaming {
                    chatService.stopStreaming()
                } else {
                    sendMessage(inputText)
                }
            } label: {
                Image(systemName: chatService.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(sendButtonColor)
            }
            .disabled(!chatService.isStreaming && inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .onChange(of: speechService.transcribedText) { _, newText in
            if !newText.isEmpty {
                inputText = newText
            }
        }
        .onChange(of: speechService.isRecording) { wasRecording, isNow in
            // Auto-send when recording stops and we have text
            if wasRecording && !isNow && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sendMessage(inputText)
            }
        }
    }

    // MARK: - Helpers

    private var sendButtonColor: Color {
        if chatService.isStreaming { return .red }
        return inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue
    }

    private func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputText = ""
        isInputFocused = false
        chatService.send(trimmed)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let lastId = chatService.messages.last?.id else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(lastId, anchor: .bottom)
        }
    }
}

// MARK: - Message Bubble

@available(iOS 26, *)
private struct MessageBubble: View {
    let message: ChatMessage
    let isStreaming: Bool

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            HStack(alignment: .bottom, spacing: 0) {
                Text(message.content.isEmpty && isStreaming ? " " : message.content)
                if isStreaming && !message.content.isEmpty {
                    TypingCursor()
                }
            }
            .padding(12)
            .background(isUser ? Color.blue : Color(.systemGray5))
            .foregroundStyle(isUser ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            if !isUser { Spacer(minLength: 60) }
        }
    }
}

@available(iOS 26, *)
private struct TypingCursor: View {
    @State private var visible = true

    var body: some View {
        Text("|")
            .fontWeight(.light)
            .opacity(visible ? 1 : 0)
            .animation(.easeInOut(duration: 0.5).repeatForever(), value: visible)
            .onAppear { visible = false }
    }
}

@available(iOS 26, *)
struct HitResultButtons: View {
    let results: [(name: String, url: String)]
    @Binding var copiedHitId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(results, id: \.url) { result in
                Button {
                    UIPasteboard.general.string = result.url
                    copiedHitId = result.url
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()

                    // Reset copied state after 2s
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if copiedHitId == result.url {
                            copiedHitId = nil
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: copiedHitId == result.url ? "checkmark.circle.fill" : "link")
                            .foregroundStyle(copiedHitId == result.url ? .green : .blue)
                        Text(result.name)
                            .fontWeight(.medium)
                        Spacer()
                        Text(copiedHitId == result.url ? "Copied!" : "Copy Link")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = result.url
                    } label: {
                        Label("Copy Link", systemImage: "doc.on.doc")
                    }
                    ShareLink(item: URL(string: result.url)!) {
                        Label("Share Link", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}

#endif
