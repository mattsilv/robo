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

    init() {
        resetSession()
    }

    func resetSession() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        currentStreamingText = ""
        messages = []

        let prompt = Self.buildSystemPrompt()
        session = LanguageModelSession {
            prompt
        }
    }

    func send(_ text: String) {
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)

        let assistantMessage = ChatMessage(role: .assistant, content: "")
        messages.append(assistantMessage)
        isStreaming = true
        currentStreamingText = ""

        streamTask = Task { [weak self] in
            guard let self, let session else { return }
            do {
                let stream = session.streamResponse(to: text)
                for try await partial in stream {
                    guard !Task.isCancelled else { break }
                    let text = String(describing: partial)
                    self.currentStreamingText = text
                    self.messages[self.messages.count - 1].content = text
                }
            } catch is CancellationError {
                logger.debug("Stream cancelled")
            } catch {
                logger.error("Stream error: \(error.localizedDescription)")
                let errorText = self.messages[self.messages.count - 1].content
                if errorText.isEmpty {
                    self.messages[self.messages.count - 1].content = "Sorry, I couldn't generate a response. Please try again."
                }
            }
            self.isStreaming = false
            self.currentStreamingText = ""
        }
    }

    func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        currentStreamingText = ""
    }

    func prewarm() {
        session?.prewarm()
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

        Keep responses concise (2-3 sentences unless the user asks for detail). \
        Be friendly and helpful.
        """
    }
}

#endif
