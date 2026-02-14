import Foundation

enum APIError: Error {
    case invalidURL
    case requestFailed(Error)
    case invalidResponse
    case decodingError(Error)
    case httpError(statusCode: Int, message: String)
}

@Observable
class APIService {
    let deviceService: DeviceService

    init(deviceService: DeviceService) {
        self.deviceService = deviceService
    }

    private var baseURL: String {
        deviceService.config.apiBaseURL
    }

    private var deviceId: String {
        deviceService.config.id
    }

    // MARK: - Device Registration

    func registerDevice(name: String) async throws -> DeviceConfig {
        let url = try makeURL(path: "/api/devices/register")
        let payload = ["name": name]

        let response: RegisterResponse = try await post(url: url, body: payload)
        return DeviceConfig(
            id: response.id,
            name: response.name,
            apiBaseURL: baseURL,
            mcpToken: response.mcpToken
        )
    }

    // MARK: - Sensor Data

    func submitSensorData(
        sensorType: SensorData.SensorType,
        data: [String: Any]
    ) async throws -> SensorData {
        let url = try makeURL(path: "/api/sensors/data")
        let payload: [String: Any] = [
            "device_id": deviceId,
            "sensor_type": sensorType.rawValue,
            "data": data
        ]

        let response: SensorDataResponse = try await post(url: url, body: payload)
        return response.toSensorData()
    }

    // MARK: - Inbox

    func fetchInbox() async throws -> [InboxCard] {
        let url = try makeURL(path: "/api/inbox/\(deviceId)")
        let response: InboxResponse = try await get(url: url)
        return response.cards
    }

    func respondToCard(cardId: String, response: String) async throws -> InboxCard {
        let url = try makeURL(path: "/api/inbox/\(cardId)/respond")
        let payload = ["response": response]
        return try await post(url: url, body: payload)
    }

    // MARK: - Nutrition Lookup

    func lookupNutrition(upc: String) async throws -> NutritionResponse {
        let url = try makeURL(path: "/api/nutrition/lookup?upc=\(upc)")
        return try await get(url: url)
    }

    // MARK: - HTTP Methods

    private func get<T: Decodable>(url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")

        return try await performRequest(request)
    }

    private func post<T: Decodable>(url: URL, body: Any) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return try await performRequest(request)
    }

    private func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw APIError.httpError(statusCode: httpResponse.statusCode, message: message)
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        } catch let error as DecodingError {
            throw APIError.decodingError(error)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.requestFailed(error)
        }
    }

    private func makeURL(path: String) throws -> URL {
        guard let url = URL(string: baseURL + path) else {
            throw APIError.invalidURL
        }
        return url
    }
}

// MARK: - Response Models

private struct RegisterResponse: Decodable {
    let id: String
    let name: String
    let mcpToken: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case mcpToken = "mcp_token"
    }
}

private struct SensorDataResponse: Decodable {
    let id: Int
    let deviceId: String
    let sensorType: String
    let data: [String: AnyCodable]
    let capturedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case deviceId = "device_id"
        case sensorType = "sensor_type"
        case data
        case capturedAt = "captured_at"
    }

    func toSensorData() -> SensorData {
        let type = SensorData.SensorType(rawValue: sensorType) ?? .barcode
        let date = ISO8601DateFormatter().date(from: capturedAt) ?? Date()
        return SensorData(
            id: id,
            deviceId: deviceId,
            sensorType: type,
            data: data,
            capturedAt: date
        )
    }
}

private struct InboxResponse: Decodable {
    let cards: [InboxCard]
    let count: Int
}
