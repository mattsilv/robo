import Testing
@testable import Robo

// MARK: - Mock

private struct MockRegistrar: DeviceRegistering {
    var result: Result<DeviceConfig, Error>

    func registerDevice(name: String) async throws -> DeviceConfig {
        try result.get()
    }
}

private enum MockError: Error { case fail }

// MARK: - reRegister Tests

@Test func reRegisterSuccess_persistsNewTokenAndID() async {
    let oldConfig = DeviceConfig(id: "old-id-123", name: "Test", apiBaseURL: "https://api.robo.app", mcpToken: nil)
    let service = DeviceService(config: oldConfig)

    let newConfig = DeviceConfig(id: "new-id-456", name: "Test", apiBaseURL: "https://api.robo.app", mcpToken: "abc123token")
    let mock = MockRegistrar(result: .success(newConfig))

    await service.reRegister(apiService: mock)

    #expect(service.config.id == "new-id-456")
    #expect(service.config.mcpToken == "abc123token")
    #expect(service.isRegistered)
    #expect(service.registrationError == nil)
}

@Test func reRegisterFailure_restoresOldConfig() async {
    let oldConfig = DeviceConfig(id: "old-id-123", name: "Test", apiBaseURL: "https://api.robo.app", mcpToken: nil)
    let service = DeviceService(config: oldConfig)

    let mock = MockRegistrar(result: .failure(MockError.fail))

    await service.reRegister(apiService: mock)

    // Old config should be restored — device ID must NOT be wiped
    #expect(service.config.id == "old-id-123")
    #expect(service.config.name == "Test")
    #expect(service.registrationError != nil)
}

@Test func reRegisterFailure_doesNotWipeDeviceID() async {
    // This is the exact bug from issue #139:
    // Before the fix, reRegister would save "unregistered" before bootstrap,
    // so a failed bootstrap left the user with a wiped device ID.
    let oldConfig = DeviceConfig(id: "052fa9ba-9d43-4327-94fb-7687626bb235", name: "Matt's iPhone", apiBaseURL: "https://api.robo.app", mcpToken: nil)
    let service = DeviceService(config: oldConfig)

    let mock = MockRegistrar(result: .failure(MockError.fail))

    await service.reRegister(apiService: mock)

    #expect(service.config.id == "052fa9ba-9d43-4327-94fb-7687626bb235")
    #expect(service.config.id != DeviceConfig.unregisteredID)
}
