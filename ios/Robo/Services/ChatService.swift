import Foundation
import os

private let logger = Logger(subsystem: "com.silv.Robo", category: "ChatService")

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26, *)
@MainActor
@Observable
class ChatService {
    var messages: [ChatMessage] = []
    var isStreaming = false
    private(set) var currentStreamingText = ""

    /// HIT results from tool calls — maps message ID to array of (name, url)
    var hitResults: [UUID: [(name: String, url: String)]] = [:]

    private var session: LanguageModelSession?
    private var streamTask: Task<Void, Never>?
    private var activeAssistantMessageId: UUID?
    private var apiService: APIService?

    init() {}

    func configure(apiService: APIService) {
        self.apiService = apiService
        resetSession()
    }

    func resetSession() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        currentStreamingText = ""
        activeAssistantMessageId = nil
        messages = []
        hitResults = [:]

        let prompt = Self.buildSystemPrompt()

        if let apiService {
            let tool = CreateAvailabilityHITTool(apiService: apiService)
            session = LanguageModelSession(tools: [tool]) {
                prompt
            }
        } else {
            session = LanguageModelSession {
                prompt
            }
        }
    }

    func send(_ text: String) {
        // Cancel any in-flight stream before starting a new one
        if isStreaming {
            streamTask?.cancel()
            streamTask = nil
            isStreaming = false
            currentStreamingText = ""
            activeAssistantMessageId = nil
        }

        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)

        let assistantMessage = ChatMessage(role: .assistant, content: "")
        let targetId = assistantMessage.id
        messages.append(assistantMessage)
        activeAssistantMessageId = targetId
        isStreaming = true
        currentStreamingText = ""

        streamTask = Task { [weak self] in
            guard let self, let session else { return }

            do {
                if self.apiService != nil {
                    // Use non-streaming respond() for tool calling support
                    let response = try await session.respond(to: text)
                    guard !Task.isCancelled else { return }
                    guard self.activeAssistantMessageId == targetId else { return }

                    let content = response.content
                    self.updateMessage(id: targetId, content: content)

                    // Check if the response contains HIT URLs (tool was called)
                    self.parseHitResults(content: content, messageId: targetId)
                } else {
                    // Fallback: stream without tools
                    let stream = session.streamResponse(to: text)
                    for try await partial in stream {
                        guard !Task.isCancelled else { break }
                        guard self.activeAssistantMessageId == targetId else { break }
                        let text = partial.content
                        self.currentStreamingText = text
                        self.updateMessage(id: targetId, content: text)
                    }
                }
            } catch is CancellationError {
                logger.debug("Stream cancelled")
            } catch {
                logger.error("Chat error: \(error.localizedDescription)")
                if self.activeAssistantMessageId == targetId {
                    let existing = self.messageContent(for: targetId)
                    if existing.isEmpty {
                        self.updateMessage(id: targetId, content: "Sorry, I couldn't generate a response. Please try again.")
                    }
                }
            }
            if self.activeAssistantMessageId == targetId {
                self.isStreaming = false
                self.currentStreamingText = ""
                self.activeAssistantMessageId = nil
            }
        }
    }

    func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        currentStreamingText = ""
        activeAssistantMessageId = nil
    }

    func prewarm() {
        session?.prewarm()
    }

    // MARK: - Private Helpers

    private func updateMessage(id: UUID, content: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content = content
    }

    private func messageContent(for id: UUID) -> String {
        messages.first(where: { $0.id == id })?.content ?? ""
    }

    /// Parse HIT URLs from tool output embedded in assistant response
    private func parseHitResults(content: String, messageId: UUID) {
        // Look for lines like "• Name: https://robo.app/hit/XXXX"
        let lines = content.components(separatedBy: "\n")
        var results: [(name: String, url: String)] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Match "• Name: https://robo.app/hit/..."
            if trimmed.hasPrefix("•"),
               let colonRange = trimmed.range(of: ": https://robo.app/hit/") {
                let name = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<colonRange.lowerBound])
                let url = String(trimmed[colonRange.lowerBound..<trimmed.endIndex]).dropFirst(2) // drop ": "
                results.append((name: name.trimmingCharacters(in: .whitespaces), url: String(url)))
            }
        }

        if !results.isEmpty {
            hitResults[messageId] = results
        }
    }

    static func buildSystemPrompt() -> String {
        return """
        You are Robo's on-device assistant. Robo is an iOS app that turns phone sensors \
        (LiDAR, camera, barcode scanner) into APIs for AI agents.

        You can help users create Group Think availability polls using the create_availability_poll tool. \
        When a user wants to plan something with friends (trip, dinner, meetup), guide them through:
        1. Ask who's coming (participant names)
        2. Ask for date options (suggest specific dates if they say things like "weekends in May")
        3. Ask for time slot preferences
        Then call the tool to create the poll and share links.

        When the user mentions dates loosely (e.g. "weekends in May"), convert them to specific ISO dates. \
        For time slots, default to evening times (5 PM, 6 PM, 7 PM, 8 PM) unless the user specifies otherwise.

        IMPORTANT: Keep responses short — 1-2 sentences. Be conversational and friendly. \
        When you have enough info, call the tool immediately without asking for confirmation.
        """
    }
}

#endif
