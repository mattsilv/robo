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

    private var session: LanguageModelSession?
    private var streamTask: Task<Void, Never>?
    private var activeAssistantMessageId: UUID?

    init() {
        resetSession()
    }

    func resetSession() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        currentStreamingText = ""
        activeAssistantMessageId = nil
        messages = []

        let prompt = Self.buildSystemPrompt()
        session = LanguageModelSession {
            prompt
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
                let stream = session.streamResponse(to: text)
                for try await partial in stream {
                    guard !Task.isCancelled else { break }
                    guard self.activeAssistantMessageId == targetId else { break }
                    let text = partial.content
                    self.currentStreamingText = text
                    self.updateMessage(id: targetId, content: text)
                }
            } catch is CancellationError {
                logger.debug("Stream cancelled")
            } catch {
                logger.error("Stream error: \(error.localizedDescription)")
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

    static func buildSystemPrompt() -> String {
        let agents = MockAgentService.loadAgents()
        let agentDescriptions = agents.map { agent in
            var line = "- \(agent.name): \(agent.description)"
            if let request = agent.pendingRequest {
                let skill = String(describing: request.skillType)
                line += " [Sensor: \(skill)]"
            }
            return line
        }.joined(separator: "\n")

        return """
        You are Robo's on-device assistant. Robo is an iOS app that turns phone sensors \
        (LiDAR, camera, barcode scanner, Bluetooth beacons, motion, health) into APIs for AI agents.

        Available agents:
        \(agentDescriptions)

        Robo's sensors: LiDAR (room scanning), Camera (photos), Barcode Scanner, \
        Bluetooth Beacons (proximity), Motion (steps, activity), Health (sleep, workouts).

        You help users understand what Robo can do and how to use each agent. \
        You CANNOT perform actions like scanning or capturing. When asked to perform an action, \
        explain how the user can do it themselves using the Capture tab. \
        Action capabilities are coming in a future update.

        IMPORTANT: Keep responses very short — 1-2 sentences max. \
        Only give longer answers if the user explicitly asks for detail. \
        Never use bullet points or lists unless asked. Be direct and conversational.
        """
    }
}

#endif
