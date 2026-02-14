import Foundation
import CoreBluetooth
import os

private let logger = Logger(subsystem: "com.silv.Robo", category: "SensorProvisioning")

// MARK: - UUID Constants

enum SensorUUID {
    static let provisioningService = CBUUID(string: "12345678-9ABC-DEF0-1234-000000000001")
    static let ssid     = CBUUID(string: "12345678-9ABC-DEF0-1234-000000000002")
    static let password = CBUUID(string: "12345678-9ABC-DEF0-1234-000000000003")
    static let roomName = CBUUID(string: "12345678-9ABC-DEF0-1234-000000000004")
    static let minorID  = CBUUID(string: "12345678-9ABC-DEF0-1234-000000000005")
    static let command  = CBUUID(string: "12345678-9ABC-DEF0-1234-000000000006")
    static let status   = CBUUID(string: "12345678-9ABC-DEF0-1234-000000000007")
}

// MARK: - Provisioning State

enum ProvisioningState: Equatable {
    case idle
    case scanning
    case connecting
    case discoveringServices
    case ready
    case writing
    case saving
    case saved
    case error(String)
    case disconnected
}

// MARK: - Discovered Sensor

struct DiscoveredSensor: Identifiable {
    let id: UUID  // CBPeripheral identifier
    let peripheral: CBPeripheral
    let name: String
    let rssi: Int

    static func == (lhs: DiscoveredSensor, rhs: DiscoveredSensor) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Room Presets

struct RoomPreset: Identifiable {
    let id = UUID()
    let name: String
    let minorID: UInt16
}

let roomPresets: [RoomPreset] = [
    RoomPreset(name: "Office",      minorID: 1),
    RoomPreset(name: "Kitchen",     minorID: 2),
    RoomPreset(name: "Bedroom",     minorID: 3),
    RoomPreset(name: "Living Room", minorID: 4),
    RoomPreset(name: "Garage",      minorID: 5),
    RoomPreset(name: "Bathroom",    minorID: 6),
]

// MARK: - SensorProvisioningManager

@Observable
class SensorProvisioningManager: NSObject {

    private(set) var state: ProvisioningState = .idle
    private(set) var discoveredSensors: [DiscoveredSensor] = []
    private(set) var bluetoothState: CBManagerState = .unknown

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var characteristics: [CBUUID: CBCharacteristic] = [:]

    // Pending scan request before Bluetooth is powered on
    private var pendingScan = false

    // Write tracking
    private var pendingWriteCount = 0
    private var completedWriteCount = 0

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Public API

    func startScanning() {
        discoveredSensors = []

        guard centralManager.state == .poweredOn else {
            pendingScan = true
            state = .scanning
            logger.info("Bluetooth not ready, will scan when powered on")
            return
        }

        state = .scanning
        // Scan with nil services — engineer confirmed service UUID not in advertisement data
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        logger.info("Started BLE scan for Robo Sensors")
    }

    func stopScanning() {
        centralManager.stopScan()
        if state == .scanning {
            state = .idle
        }
        pendingScan = false
    }

    func connect(to sensor: DiscoveredSensor) {
        centralManager.stopScan()
        connectedPeripheral = sensor.peripheral
        sensor.peripheral.delegate = self
        state = .connecting
        centralManager.connect(sensor.peripheral, options: nil)
        logger.info("Connecting to \(sensor.name)")
    }

    func provision(ssid: String, password: String, roomName: String, minorID: UInt16) {
        guard let peripheral = connectedPeripheral else {
            state = .error("No connected sensor")
            return
        }

        state = .writing
        pendingWriteCount = 0
        completedWriteCount = 0

        // Write SSID
        if let char = characteristics[SensorUUID.ssid],
           let data = ssid.data(using: .utf8) {
            peripheral.writeValue(data, for: char, type: .withResponse)
            pendingWriteCount += 1
        }

        // Write password
        if let char = characteristics[SensorUUID.password],
           let data = password.data(using: .utf8) {
            peripheral.writeValue(data, for: char, type: .withResponse)
            pendingWriteCount += 1
        }

        // Write room name
        if let char = characteristics[SensorUUID.roomName],
           let data = roomName.data(using: .utf8) {
            peripheral.writeValue(data, for: char, type: .withResponse)
            pendingWriteCount += 1
        }

        // Write minor ID (big-endian uint16)
        if let char = characteristics[SensorUUID.minorID] {
            var bigEndian = minorID.bigEndian
            let data = Data(bytes: &bigEndian, count: MemoryLayout<UInt16>.size)
            peripheral.writeValue(data, for: char, type: .withResponse)
            pendingWriteCount += 1
        }

        logger.info("Writing \(self.pendingWriteCount) characteristics")
    }

    func cancel() {
        centralManager.stopScan()
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        cleanup()
    }

    // MARK: - Private

    private func sendSaveCommand() {
        guard let peripheral = connectedPeripheral,
              let cmdChar = characteristics[SensorUUID.command],
              let data = "SAVE".data(using: .utf8) else { return }

        // Subscribe to status notifications before sending SAVE
        if let statusChar = characteristics[SensorUUID.status] {
            peripheral.setNotifyValue(true, for: statusChar)
        }

        state = .saving
        peripheral.writeValue(data, for: cmdChar, type: .withResponse)
        logger.info("Sent SAVE command")
    }

    private func cleanup() {
        connectedPeripheral = nil
        characteristics.removeAll()
        pendingWriteCount = 0
        completedWriteCount = 0
        pendingScan = false
        state = .idle
    }
}

// MARK: - CBCentralManagerDelegate

extension SensorProvisioningManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        logger.info("Bluetooth state: \(String(describing: central.state.rawValue))")

        if central.state == .poweredOn, pendingScan {
            pendingScan = false
            centralManager.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
            logger.info("Bluetooth powered on, starting deferred scan")
        }
    }

    func centralManager(_ central: CBCentralManager,
                         didDiscover peripheral: CBPeripheral,
                         advertisementData: [String: Any],
                         rssi RSSI: NSNumber) {
        // Filter by name "Robo Sensor"
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? peripheral.name
        guard let name = advName, name == "Robo Sensor" else { return }

        // Don't add duplicates
        guard !discoveredSensors.contains(where: { $0.id == peripheral.identifier }) else { return }

        let sensor = DiscoveredSensor(
            id: peripheral.identifier,
            peripheral: peripheral,
            name: name,
            rssi: RSSI.intValue
        )
        discoveredSensors.append(sensor)
        logger.info("Discovered sensor: \(name), RSSI: \(RSSI.intValue)")
    }

    func centralManager(_ central: CBCentralManager,
                         didConnect peripheral: CBPeripheral) {
        state = .discoveringServices
        peripheral.discoverServices([SensorUUID.provisioningService])
        logger.info("Connected to sensor")
    }

    func centralManager(_ central: CBCentralManager,
                         didFailToConnect peripheral: CBPeripheral,
                         error: Error?) {
        state = .error("Failed to connect: \(error?.localizedDescription ?? "unknown")")
        logger.error("Connection failed: \(error?.localizedDescription ?? "unknown")")
    }

    func centralManager(_ central: CBCentralManager,
                         didDisconnectPeripheral peripheral: CBPeripheral,
                         error: Error?) {
        // After SAVE, the device reboots — disconnection is expected
        if case .saving = state {
            state = .disconnected
            logger.info("Sensor disconnected after save (expected reboot)")
        } else if case .saved = state {
            state = .disconnected
            logger.info("Sensor disconnected after saved state")
        } else {
            state = .error("Sensor disconnected unexpectedly")
            logger.error("Unexpected disconnect: \(error?.localizedDescription ?? "none")")
        }
    }
}

// MARK: - CBPeripheralDelegate

extension SensorProvisioningManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral,
                     didDiscoverServices error: Error?) {
        if let error {
            state = .error("Service discovery failed: \(error.localizedDescription)")
            return
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == SensorUUID.provisioningService }) else {
            state = .error("Provisioning service not found")
            return
        }

        peripheral.discoverCharacteristics([
            SensorUUID.ssid,
            SensorUUID.password,
            SensorUUID.roomName,
            SensorUUID.minorID,
            SensorUUID.command,
            SensorUUID.status,
        ], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral,
                     didDiscoverCharacteristicsFor service: CBService,
                     error: Error?) {
        if let error {
            state = .error("Characteristic discovery failed: \(error.localizedDescription)")
            return
        }

        guard let chars = service.characteristics else {
            state = .error("No characteristics found")
            return
        }

        for char in chars {
            characteristics[char.uuid] = char
        }

        // Subscribe to status notifications
        if let statusChar = characteristics[SensorUUID.status] {
            peripheral.setNotifyValue(true, for: statusChar)
            peripheral.readValue(for: statusChar)
        }

        logger.info("Discovered \(chars.count) characteristics")
    }

    func peripheral(_ peripheral: CBPeripheral,
                     didUpdateValueFor characteristic: CBCharacteristic,
                     error: Error?) {
        guard characteristic.uuid == SensorUUID.status,
              let data = characteristic.value,
              let statusString = String(data: data, encoding: .utf8) else { return }

        logger.info("Status update: \(statusString)")

        switch statusString {
        case "ready":
            state = .ready
        case "saved":
            state = .saved
        default:
            if statusString.hasPrefix("error:") {
                state = .error(statusString)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                     didWriteValueFor characteristic: CBCharacteristic,
                     error: Error?) {
        if let error {
            state = .error("Write failed: \(error.localizedDescription)")
            logger.error("Write failed for \(characteristic.uuid): \(error.localizedDescription)")
            return
        }

        // Don't count the SAVE command write
        guard characteristic.uuid != SensorUUID.command else { return }

        completedWriteCount += 1
        logger.info("Write \(self.completedWriteCount)/\(self.pendingWriteCount) completed")

        // All config writes done — send SAVE
        if completedWriteCount >= pendingWriteCount {
            sendSaveCommand()
        }
    }
}
