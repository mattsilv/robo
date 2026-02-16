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
    private var captureCoordinator: CaptureCoordinator?
    private var coindexService: CoindexService?

    var currentProvider: AIProvider {
        AIProvider(rawValue: UserDefaults.standard.string(forKey: "aiProvider") ?? AIProvider.openRouter.rawValue) ?? .openRouter
    }

    init() {}

    func configure(apiService: APIService, captureCoordinator: CaptureCoordinator, coindexService: CoindexService? = nil) {
        guard self.apiService == nil else { return }
        self.apiService = apiService
        self.captureCoordinator = captureCoordinator
        self.coindexService = coindexService ?? CoindexService()
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

        // Only set up Apple session if using on-device provider
        if currentProvider == .appleOnDevice {
            setupAppleSession()
        } else {
            session = nil
        }
    }

    private func setupAppleSession() {
        let prompt = Self.buildSystemPrompt()

        var tools: [any Tool] = []
        if let apiService {
            tools.append(CreateAvailabilityHITTool(apiService: apiService))
        }
        if let captureCoordinator {
            tools.append(ScanRoomTool(captureCoordinator: captureCoordinator))
            tools.append(ScanBarcodeTool(captureCoordinator: captureCoordinator))
            tools.append(TakePhotoTool(captureCoordinator: captureCoordinator))
        }

        if tools.isEmpty {
            session = LanguageModelSession {
                prompt
            }
        } else {
            session = LanguageModelSession(tools: tools) {
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

        if currentProvider == .openRouter {
            streamTask = Task { [weak self] in
                await self?.sendViaOpenRouter(text: text, targetId: targetId)
            }
        } else {
            streamTask = Task { [weak self] in
                await self?.sendViaApple(text: text, targetId: targetId)
            }
        }
    }

    // MARK: - OpenRouter (Cloud) Path

<<<<<<< HEAD
    private func sendViaOpenRouter(text: String, targetId: UUID) async {
        guard let apiService else {
            updateMessage(id: targetId, content: "Chat not configured. Please restart the app.")
            finishStream(targetId: targetId)
            return
        }
=======
                    let content = response.content
                    logger.debug("Chat response content: \(content)")
                    self.updateMessage(id: targetId, content: content)
>>>>>>> 40c716c (fix(chat): improve HIT link parsing with robust regex + fallback)

        // Build messages array with system prompt + conversation history
        var openRouterMessages: [[String: String]] = [
            ["role": "system", "content": Self.buildSystemPrompt()]
        ]
        for msg in messages.dropLast() { // dropLast to skip empty assistant placeholder
            if msg.role == .user || msg.role == .assistant {
                let role = msg.role == .user ? "user" : "assistant"
                if !msg.content.isEmpty {
                    openRouterMessages.append(["role": role, "content": msg.content])
                }
            }
        }

        let baseURL = apiService.baseURL
        guard let url = URL(string: "\(baseURL)/api/chat") else {
            updateMessage(id: targetId, content: "Invalid API URL.")
            finishStream(targetId: targetId)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiService.deviceId, forHTTPHeaderField: "X-Device-ID")

        let body: [String: Any] = ["messages": openRouterMessages]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                var errorBody = ""
                for try await line in bytes.lines {
                    errorBody += line
                    if errorBody.count > 500 { break }
                }
                logger.error("OpenRouter proxy error \(httpResponse.statusCode): \(errorBody)")
                updateMessage(id: targetId, content: "Cloud model error (\(httpResponse.statusCode)). Try again or switch to Apple on-device in Settings.")
                finishStream(targetId: targetId)
                return
            }

            var accumulated = ""
            for try await line in bytes.lines {
                guard !Task.isCancelled else { break }
                guard activeAssistantMessageId == targetId else { break }

                guard line.hasPrefix("data: ") else { continue }
                let jsonStr = String(line.dropFirst(6))
                if jsonStr == "[DONE]" { break }

                // Parse SSE chunk: {"choices":[{"delta":{"content":"..."}}]}
                if let data = jsonStr.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let delta = choices.first?["delta"] as? [String: Any],
                   let content = delta["content"] as? String {
                    accumulated += content
                    currentStreamingText = accumulated
                    updateMessage(id: targetId, content: accumulated)
                }
            }
        } catch is CancellationError {
            logger.debug("OpenRouter stream cancelled")
        } catch {
            logger.error("OpenRouter stream error: \(error.localizedDescription)")
            if messageContent(for: targetId).isEmpty {
                updateMessage(id: targetId, content: "Connection error. Check your network and try again.")
            }
        }

        finishStream(targetId: targetId)
    }

    // MARK: - Apple Foundation Models (On-Device) Path

    private func sendViaApple(text: String, targetId: UUID) async {
        guard let session else {
            // Session might not exist if user switched providers mid-conversation
            setupAppleSession()
            guard self.session != nil else {
                updateMessage(id: targetId, content: "Apple AI not available on this device.")
                finishStream(targetId: targetId)
                return
            }
            await sendViaApple(text: text, targetId: targetId)
            return
        }

        do {
            if apiService != nil || captureCoordinator != nil {
                let response = try await session.respond(to: text)
                guard !Task.isCancelled else { return }
                guard activeAssistantMessageId == targetId else { return }

                let content = response.content
                updateMessage(id: targetId, content: content)
                parseHitResults(content: content, messageId: targetId)
            } else {
                let stream = session.streamResponse(to: text)
                for try await partial in stream {
                    guard !Task.isCancelled else { break }
                    guard activeAssistantMessageId == targetId else { break }
                    let text = partial.content
                    currentStreamingText = text
                    updateMessage(id: targetId, content: text)
                }
            }
        } catch is CancellationError {
            logger.debug("Stream cancelled")
            if activeAssistantMessageId == targetId {
                let existing = messageContent(for: targetId)
                if existing.isEmpty {
                    updateMessage(id: targetId, content: "Capture cancelled. Let me know if you'd like to try again.")
                }
            }
        } catch {
            logger.error("Chat error: \(error.localizedDescription)")
            if activeAssistantMessageId == targetId {
                let existing = messageContent(for: targetId)
                if existing.isEmpty {
                    updateMessage(id: targetId, content: "Sorry, I couldn't generate a response. Please try again.")
                }
            }
        }

        finishStream(targetId: targetId)
    }

    private func finishStream(targetId: UUID) {
        if activeAssistantMessageId == targetId {
            isStreaming = false
            currentStreamingText = ""
            activeAssistantMessageId = nil
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
        logger.debug("Parsing HIT results from content: \(content.prefix(500))")

        var results: [(name: String, url: String)] = []

        // Strategy 1: Try regex to find all robo.app/hit URLs with context
        let pattern = "(?:•|\\-|\\*|\\d+\\.)\\s*([^:\\n]+):\\s*(https://robo\\.app/hit/[a-zA-Z0-9\\-]+)"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsContent = content as NSString
            let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))

            for match in matches {
                if match.numberOfRanges == 3 {
                    let nameRange = match.range(at: 1)
                    let urlRange = match.range(at: 2)

                    if nameRange.location != NSNotFound, urlRange.location != NSNotFound {
                        let name = nsContent.substring(with: nameRange).trimmingCharacters(in: .whitespaces)
                        let url = nsContent.substring(with: urlRange)
                        results.append((name: name, url: url))
                        logger.debug("Matched regex pattern: name=\(name), url=\(url)")
                    }
                }
            }
        }

        // Strategy 2: Fallback - find any robo.app/hit URLs and try to extract names from context
        if results.isEmpty {
            logger.debug("Strategy 1 failed, trying fallback extraction")

            // Find all URLs
            let urlPattern = "https://robo\\.app/hit/[a-zA-Z0-9\\-]+"
            if let urlRegex = try? NSRegularExpression(pattern: urlPattern, options: []) {
                let nsContent = content as NSString
                let urlMatches = urlRegex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))

                for urlMatch in urlMatches {
                    let url = nsContent.substring(with: urlMatch.range)

                    // Try to find a name near this URL (look backwards up to 50 chars)
                    let searchStart = max(0, urlMatch.range.location - 50)
                    let searchRange = NSRange(location: searchStart, length: urlMatch.range.location - searchStart)
                    let context = nsContent.substring(with: searchRange)

                    // Look for patterns like "Name:", "Name -", or just "Name"
                    let lines = context.components(separatedBy: CharacterSet.newlines)
                    if let lastLine = lines.last {
                        let cleaned = lastLine
                            .replacingOccurrences(of: "•", with: "")
                            .replacingOccurrences(of: "-", with: "")
                            .replacingOccurrences(of: "*", with: "")
                            .replacingOccurrences(of: ":", with: "")
                            .trimmingCharacters(in: .whitespaces)

                        let name = cleaned.isEmpty ? "Link" : cleaned
                        results.append((name: name, url: url))
                        logger.debug("Fallback extraction: name=\(name), url=\(url)")
                    }
                }
            }
        }

        logger.debug("Found \(results.count) HIT results")
        if !results.isEmpty {
            hitResults[messageId] = results
        }
    }

    static func buildSystemPrompt(includingTools: Bool = true) -> String {
        let sensorSkills = FeatureRegistry.activeSkills
            .filter { $0.category == .sensor || $0.category == .workflow }
            .map { "- \($0.name): \($0.tagline)" }
            .joined(separator: "\n")

        let comingSoon = FeatureRegistry.comingSoonSkills
            .map { $0.name }
            .joined(separator: ", ")

        var prompt = """
        You are \(AppCopy.App.name)'s assistant. \(AppCopy.App.name) is an iOS app that turns phone sensors \
        (LiDAR, camera, barcode scanner) into APIs for AI agents.

        Available sensor capabilities:
        \(sensorSkills)

        Coming soon: \(comingSoon)
        """

        if includingTools {
            prompt += """

            You have these tools — use them when the user asks:
            - scan_room: Launches LiDAR to scan and measure a room. Use when user says "scan my room", \
            "measure the kitchen", "map the bedroom", etc.
            - scan_barcode: Launches the barcode scanner. Use when user says "scan a barcode", \
            "look up this product", "scan a QR code", etc.
            - take_photo: Launches the camera to capture photos. Use when user says "take a photo", \
            "photograph my desk", "capture the label", etc.
            - create_availability_poll: Creates a group availability poll with shareable links.

            When the user asks to scan, photograph, or capture something, call the appropriate tool \
            immediately. Do NOT tell them to go to the Capture tab — you can do it directly.

            After a room scan, you'll receive dimensions and details. Use this to answer follow-up \
            questions like "could a queen bed fit?" or "how much paint do I need?".
            """
        }

        prompt += """

        IMPORTANT: Keep responses short — 1-2 sentences. Be conversational and friendly. \
        Never output raw tool calls or code blocks. Just respond naturally.
        """

        return prompt
    }
}

#endif
