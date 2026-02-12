import SwiftUI
import SwiftData

// MARK: - Browse Mode

private enum BrowseMode: String, CaseIterable {
    case byAgent = "By Agent"
    case byType = "By Type"
}

struct ScanHistoryView: View {
    @Query(sort: \ScanRecord.capturedAt, order: .reverse)
    private var scans: [ScanRecord]
    @Query(sort: \RoomScanRecord.capturedAt, order: .reverse)
    private var roomScans: [RoomScanRecord]
    @Query(sort: \MotionRecord.capturedAt, order: .reverse)
    private var motionRecords: [MotionRecord]
    @Query(sort: \AgentCompletionRecord.completedAt, order: .reverse)
    private var completionRecords: [AgentCompletionRecord]
    @Query(sort: \ProductCaptureRecord.capturedAt, order: .reverse)
    private var productCaptures: [ProductCaptureRecord]
    @Query(sort: \BeaconEventRecord.capturedAt, order: .reverse)
    private var beaconEvents: [BeaconEventRecord]
    @Environment(\.modelContext) private var modelContext

    @State private var browseMode: BrowseMode = .byAgent
    @State private var selectedSegment = 0
    @State private var showingClearConfirmation = false
    @State private var shareURL: URL?
    @State private var isExporting = false
    @State private var showingBarcodeScanner = false
    @State private var showingLiDARScanner = false
    @State private var showingMotionCapture = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Browse", selection: $browseMode) {
                    ForEach(BrowseMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                if browseMode == .byType {
                    Picker("Type", selection: $selectedSegment) {
                        Text("Barcodes").tag(0)
                        Text("Rooms").tag(1)
                        Text("Motion").tag(2)
                        Text("Beacons").tag(3)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 6)
                }

                Spacer().frame(height: 8)

                if browseMode == .byAgent {
                    agentDataList
                } else {
                    Group {
                        switch selectedSegment {
                        case 0: barcodeList
                        case 1: roomList
                        case 2: motionList
                        case 3: beaconList
                        default: barcodeList
                        }
                    }
                }
            }
            .navigationTitle("My Data")
            .navigationDestination(for: ScanRecord.self) { scan in
                BarcodeDetailView(scan: scan)
            }
            .navigationDestination(for: RoomScanRecord.self) { room in
                RoomDetailView(room: room)
            }
            .navigationDestination(for: MotionRecord.self) { motion in
                MotionDetailView(motion: motion)
            }
            .navigationDestination(for: ProductCaptureRecord.self) { product in
                ProductDetailView(product: product)
            }
            .toolbar {
                if browseMode == .byType {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            exportAll()
                        } label: {
                            if isExporting {
                                ProgressView()
                            } else {
                                Label("Export All", systemImage: "square.and.arrow.up")
                            }
                        }
                        .disabled(isExporting || (scans.isEmpty && roomScans.isEmpty && motionRecords.isEmpty))
                    }

                    if (selectedSegment == 0 && !scans.isEmpty) ||
                       (selectedSegment == 1 && !roomScans.isEmpty) ||
                       (selectedSegment == 2 && !motionRecords.isEmpty) ||
                       (selectedSegment == 3 && !beaconEvents.isEmpty) {
                        ToolbarItem(placement: .destructiveAction) {
                            Button("Clear All", role: .destructive) {
                                showingClearConfirmation = true
                            }
                        }
                    }
                }
            }
            .confirmationDialog(
                "Clear All?",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete All", role: .destructive) {
                    clearAll()
                }
            } message: {
                switch selectedSegment {
                case 0:
                    Text("This will permanently delete \(scans.count) scan\(scans.count == 1 ? "" : "s").")
                case 1:
                    Text("This will permanently delete \(roomScans.count) room scan\(roomScans.count == 1 ? "" : "s").")
                case 2:
                    Text("This will permanently delete \(motionRecords.count) motion record\(motionRecords.count == 1 ? "" : "s").")
                case 3:
                    Text("This will permanently delete \(beaconEvents.count) beacon event\(beaconEvents.count == 1 ? "" : "s").")
                default:
                    Text("This will permanently delete all items.")
                }
            }
            .sheet(isPresented: Binding(
                get: { shareURL != nil },
                set: { if !$0 { shareURL = nil } }
            )) {
                if let shareURL {
                    ActivityView(activityItems: [shareURL])
                }
            }
            .fullScreenCover(isPresented: $showingBarcodeScanner) {
                BarcodeScannerView()
            }
            .fullScreenCover(isPresented: $showingLiDARScanner) {
                LiDARScanView()
            }
            .fullScreenCover(isPresented: $showingMotionCapture) {
                MotionCaptureView()
            }
        }
    }

    // MARK: - By Agent View

    @ViewBuilder
    private var agentDataList: some View {
        let agentRooms = Dictionary(grouping: roomScans.filter { $0.agentId != nil }) { $0.agentId! }
        let agentBarcodes = Dictionary(grouping: scans.filter { $0.agentId != nil }) { $0.agentId! }
        let agentMotion = Dictionary(grouping: motionRecords.filter { $0.agentId != nil }) { $0.agentId! }
        let agentCompletions = Dictionary(grouping: completionRecords) { $0.agentId }
        let agentProducts = Dictionary(grouping: productCaptures.filter { $0.agentId != nil }) { $0.agentId! }
        let allAgentIds = Set(agentRooms.keys)
            .union(agentBarcodes.keys)
            .union(agentMotion.keys)
            .union(agentCompletions.keys)
            .union(agentProducts.keys)

        let unlinkedRooms = roomScans.filter { $0.agentId == nil }
        let unlinkedBarcodes = scans.filter { $0.agentId == nil }
        let unlinkedMotion = motionRecords.filter { $0.agentId == nil }
        let hasUnlinked = !unlinkedRooms.isEmpty || !unlinkedBarcodes.isEmpty || !unlinkedMotion.isEmpty

        if allAgentIds.isEmpty && !hasUnlinked {
            ContentUnavailableView {
                Label("No Agent Data Yet", systemImage: "tray")
            } description: {
                Text("When you capture data for an agent, it appears here grouped by agent.")
            } actions: {
                Button("Scan Room") { showingLiDARScanner = true }
                Button("Scan Barcode") { showingBarcodeScanner = true }
            }
        } else {
            List {
                ForEach(Array(allAgentIds).sorted(), id: \.self) { agentId in
                    let name = AgentStore.name(for: agentId, fallback: agentRooms[agentId]?.first?.agentName
                        ?? agentBarcodes[agentId]?.first?.agentName
                        ?? agentMotion[agentId]?.first?.agentName
                        ?? agentCompletions[agentId]?.first?.agentName
                        ?? agentProducts[agentId]?.first?.agentName)

                    Section {
                        // Room scans for this agent
                        if let rooms = agentRooms[agentId] {
                            ForEach(rooms) { room in
                                NavigationLink(value: room) {
                                    RoomScanRow(room: room)
                                }
                            }
                        }
                        // Barcode scans for this agent
                        if let barcodes = agentBarcodes[agentId] {
                            ForEach(barcodes) { scan in
                                NavigationLink(value: scan) {
                                    ScanRow(scan: scan)
                                }
                            }
                        }
                        // Motion records for this agent
                        if let motion = agentMotion[agentId] {
                            ForEach(motion) { record in
                                NavigationLink(value: record) {
                                    MotionRow(motion: record)
                                }
                            }
                        }
                        // Product captures for this agent
                        if let products = agentProducts[agentId] {
                            ForEach(products) { product in
                                NavigationLink(value: product) {
                                    ProductCaptureRow(product: product)
                                }
                            }
                        }
                        // Photo completion records (no data record, just completion event)
                        if let completions = agentCompletions[agentId] {
                            let photoCompletions = completions.filter { $0.skillType == "camera" }
                            ForEach(photoCompletions) { completion in
                                HStack {
                                    Image(systemName: "camera.fill")
                                        .font(.title3)
                                        .foregroundColor(.accentColor)
                                        .frame(width: 32)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(completion.itemCount) photo\(completion.itemCount == 1 ? "" : "s") captured")
                                            .font(.subheadline)
                                        Text(completion.completedAt, style: .relative)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    } header: {
                        HStack(spacing: 8) {
                            Image(systemName: AgentStore.icon(for: agentId))
                                .font(.caption)
                                .foregroundStyle(AgentStore.color(for: agentId))
                            Text(name)
                        }
                    }
                }

                // Unlinked scans section
                if hasUnlinked {
                    Section {
                        ForEach(unlinkedRooms) { room in
                            NavigationLink(value: room) {
                                RoomScanRow(room: room)
                            }
                        }
                        ForEach(unlinkedBarcodes) { scan in
                            NavigationLink(value: scan) {
                                ScanRow(scan: scan)
                            }
                        }
                        ForEach(unlinkedMotion) { record in
                            NavigationLink(value: record) {
                                MotionRow(motion: record)
                            }
                        }
                    } header: {
                        HStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Direct Captures")
                        }
                    }
                }

                // Quick capture section
                Section("Quick Capture") {
                    Button { showingLiDARScanner = true } label: {
                        Label("Scan Room", systemImage: "camera.metering.spot")
                    }
                    Button { showingBarcodeScanner = true } label: {
                        Label("Scan Barcode", systemImage: "barcode.viewfinder")
                    }
                    Button { showingMotionCapture = true } label: {
                        Label("Capture Motion", systemImage: "figure.walk.motion")
                    }
                }
            }
        }
    }

    // MARK: - Barcode List

    @ViewBuilder
    private var barcodeList: some View {
        if scans.isEmpty {
            ContentUnavailableView {
                Label("No Scans Yet", systemImage: "barcode.viewfinder")
            } description: {
                Text("Scan barcodes and QR codes to see them here.")
            } actions: {
                Button("Scan Barcode") {
                    showingBarcodeScanner = true
                }
            }
        } else {
            List {
                ForEach(scans) { scan in
                    NavigationLink(value: scan) {
                        ScanRow(scan: scan)
                    }
                }
                .onDelete(perform: deleteBarcodeScans)

                exportAllSection
            }
        }
    }

    // MARK: - Room List

    @ViewBuilder
    private var roomList: some View {
        if roomScans.isEmpty {
            ContentUnavailableView {
                Label("No Room Scans Yet", systemImage: "camera.metering.spot")
            } description: {
                Text("Scan rooms with LiDAR to see them here.")
            } actions: {
                Button("Scan Room") {
                    showingLiDARScanner = true
                }
            }
        } else {
            List {
                ForEach(roomScans) { room in
                    NavigationLink(value: room) {
                        RoomScanRow(room: room)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            exportRoom(room)
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .tint(.blue)

                        Button(role: .destructive) {
                            modelContext.delete(room)
                            try? modelContext.save()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            exportRoom(room)
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .tint(.blue)
                    }
                }
                .onDelete(perform: deleteRoomScans)

                exportAllSection
            }
        }
    }

    // MARK: - Motion List

    @ViewBuilder
    private var motionList: some View {
        if motionRecords.isEmpty {
            ContentUnavailableView {
                Label("No Motion Data Yet", systemImage: "figure.walk.motion")
            } description: {
                Text("Capture motion & activity data to see it here.")
            } actions: {
                Button("Capture Motion") {
                    showingMotionCapture = true
                }
            }
        } else {
            List {
                ForEach(motionRecords) { motion in
                    NavigationLink(value: motion) {
                        MotionRow(motion: motion)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            modelContext.delete(motion)
                            try? modelContext.save()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onDelete(perform: deleteMotionRecords)

                exportAllSection
            }
        }
    }

    // MARK: - Beacon List

    @ViewBuilder
    private var beaconList: some View {
        if beaconEvents.isEmpty {
            ContentUnavailableView {
                Label("No Beacon Events Yet", systemImage: "sensor.tag.radiowaves.forward")
            } description: {
                Text("Start beacon monitoring to see enter/exit events here.")
            }
        } else {
            List {
                ForEach(beaconEvents) { event in
                    BeaconEventRow(event: event)
                }
                .onDelete(perform: deleteBeaconEvents)
            }
        }
    }

    // MARK: - Export All Section

    private var totalItemCount: Int {
        scans.count + roomScans.count + motionRecords.count + beaconEvents.count
    }

    @ViewBuilder
    private var exportAllSection: some View {
        Section {
            Button {
                exportAll()
            } label: {
                HStack {
                    Spacer()
                    if isExporting {
                        ProgressView()
                            .padding(.trailing, 8)
                    }
                    Label("Export All Data (\(totalItemCount))", systemImage: "square.and.arrow.up")
                    Spacer()
                }
            }
            .disabled(isExporting)
        }
    }

    // MARK: - Actions

    private func deleteBarcodeScans(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(scans[index])
        }
        try? modelContext.save()
    }

    private func deleteRoomScans(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(roomScans[index])
        }
        try? modelContext.save()
    }

    private func deleteMotionRecords(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(motionRecords[index])
        }
        try? modelContext.save()
    }

    private func deleteBeaconEvents(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(beaconEvents[index])
        }
        try? modelContext.save()
    }

    private func clearAll() {
        switch selectedSegment {
        case 0:
            for scan in scans { modelContext.delete(scan) }
        case 1:
            for room in roomScans { modelContext.delete(room) }
        case 2:
            for motion in motionRecords { modelContext.delete(motion) }
        case 3:
            for event in beaconEvents { modelContext.delete(event) }
        default:
            break
        }
        try? modelContext.save()
    }

    private func exportRoom(_ room: RoomScanRecord) {
        // Extract SwiftData model properties before crossing isolation boundary
        let name = room.roomName
        let summary = room.summaryJSON
        let fullData = room.fullRoomDataJSON
        Task.detached {
            do {
                let url = try ExportService.createRoomExportZipFromData(
                    roomName: name,
                    summaryJSON: summary,
                    fullRoomDataJSON: fullData
                )
                await MainActor.run {
                    shareURL = url
                }
            } catch {
                // Silently fail
            }
        }
    }

    private func exportAll() {
        isExporting = true
        let barcodeData = scans.map {
            ExportableScan(barcodeValue: $0.barcodeValue, symbology: $0.symbology, capturedAt: $0.capturedAt, foodName: $0.foodName, brandName: $0.brandName, calories: $0.calories, protein: $0.protein, totalFat: $0.totalFat, totalCarbs: $0.totalCarbs, dietaryFiber: $0.dietaryFiber, sugars: $0.sugars, sodium: $0.sodium, servingQty: $0.servingQty, servingUnit: $0.servingUnit, servingWeightGrams: $0.servingWeightGrams)
        }
        let roomData = roomScans.map {
            (name: $0.roomName, summaryJSON: $0.summaryJSON, fullRoomDataJSON: $0.fullRoomDataJSON)
        }
        let motionData = motionRecords.map { $0.activityJSON }
        Task.detached {
            do {
                let url = try ExportService.createCombinedExportZip(
                    scans: barcodeData,
                    rooms: roomData,
                    motionRecords: motionData
                )
                await MainActor.run {
                    shareURL = url
                    isExporting = false
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                }
            }
        }
    }
}

// MARK: - Scan Row

struct ScanRow: View {
    let scan: ScanRecord
    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            if scan.foodName != nil {
                // Product thumbnail
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.secondary.opacity(0.15))
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "fork.knife")
                                .foregroundStyle(.secondary)
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(scan.foodName ?? "")
                        .font(.subheadline)
                        .lineLimit(1)

                    if let brand = scan.brandName {
                        Text(brand)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let cal = scan.calories {
                    Text("\(Int(cal)) cal")
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            } else {
                // Barcode-only fallback
                VStack(alignment: .leading, spacing: 4) {
                    Text(scan.barcodeValue)
                        .font(.subheadline.monospaced())
                        .lineLimit(1)

                    Text(scan.capturedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(formatSymbology(scan.symbology))
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .task {
            if let urlStr = scan.photoThumbURL {
                thumbnail = ImageCacheService.cachedImage(for: urlStr)
                if thumbnail == nil {
                    await ImageCacheService.prefetch(urlString: urlStr)
                    thumbnail = ImageCacheService.cachedImage(for: urlStr)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(scan.foodName ?? "Barcode \(scan.barcodeValue)")
        .accessibilityHint("Tap to view details")
    }

    private func formatSymbology(_ raw: String) -> String {
        raw.replacingOccurrences(of: "VNBarcodeSymbology", with: "")
    }
}

// MARK: - Room Scan Row

struct RoomScanRow: View {
    let room: RoomScanRecord

    var body: some View {
        HStack {
            Image(systemName: "camera.metering.spot")
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(room.roomName)
                    .font(.subheadline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label("\(room.wallCount) walls", systemImage: "square.split.2x1")
                    Text(String(format: "%.0f ft\u{00B2}", room.floorAreaSqM * RoomDataProcessor.sqmToSqft))
                    if room.ceilingHeightM > 0 {
                        Text(String(format: "%.1fft ceil", room.ceilingHeightM * RoomDataProcessor.metersToFeet))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(room.capturedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Motion Row

struct MotionRow: View {
    let motion: MotionRecord

    private var distanceMiles: Double {
        motion.distanceMeters * MotionService.metersToMiles
    }

    var body: some View {
        HStack {
            Image(systemName: "figure.walk.motion")
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(motion.stepCount) steps")
                    .font(.subheadline)

                HStack(spacing: 8) {
                    Text(String(format: "%.1f mi", distanceMiles))
                    if motion.floorsAscended > 0 {
                        Label("\(motion.floorsAscended) floors", systemImage: "arrow.up")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(motion.capturedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Product Capture Row

struct ProductCaptureRow: View {
    let product: ProductCaptureRecord
    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            // Photo thumbnail
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.orange.opacity(0.15))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "fork.knife")
                            .foregroundStyle(.orange)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(product.foodName ?? displayName)
                    .font(.subheadline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let barcode = product.barcodeValue {
                        Text(barcode)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Label("\(product.photoCount) photos", systemImage: "photo.stack")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let cal = product.calories {
                Text("\(Int(cal)) cal")
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.15))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
            } else {
                Text(product.capturedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            // Load first photo thumbnail
            if let firstName = product.photoFileNames.first {
                thumbnail = PhotoStorageService.loadThumbnail(firstName)
            }
        }
    }

    private var displayName: String {
        if let brand = product.brandName {
            return brand
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return "Product \(formatter.string(from: product.capturedAt))"
    }
}

// MARK: - Beacon Event Row

struct BeaconEventRow: View {
    let event: BeaconEventRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.eventType == "enter" ? "arrow.right.circle.fill" : "arrow.left.circle.fill")
                .font(.title3)
                .foregroundColor(event.eventType == "enter" ? .green : .orange)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(event.eventType == "enter" ? "Entered" : "Exited")
                        .font(.subheadline.weight(.medium))
                    Text(event.roomName ?? "Beacon \(event.beaconMinor)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    if let proximity = event.proximity {
                        Text(proximity)
                            .font(.caption)
                    }
                    Text("Minor: \(event.beaconMinor)")
                        .font(.caption.monospaced())
                    if let distance = event.distanceMeters {
                        Text(String(format: "%.1fm", distance))
                            .font(.caption)
                    }
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(event.capturedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                webhookStatusBadge
            }
        }
    }

    @ViewBuilder
    private var webhookStatusBadge: some View {
        switch event.webhookStatus {
        case "sent":
            Text("Sent")
                .font(.caption2)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.green.opacity(0.15))
                .foregroundStyle(.green)
                .clipShape(Capsule())
        case "failed":
            Text("Failed")
                .font(.caption2)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.red.opacity(0.15))
                .foregroundStyle(.red)
                .clipShape(Capsule())
        case "pending":
            Text("Pending")
                .font(.caption2)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.yellow.opacity(0.15))
                .foregroundStyle(.yellow)
                .clipShape(Capsule())
        default:
            EmptyView()
        }
    }
}

#Preview {
    ScanHistoryView()
        .modelContainer(for: [ScanRecord.self, RoomScanRecord.self, MotionRecord.self, AgentCompletionRecord.self, ProductCaptureRecord.self, BeaconEventRecord.self], inMemory: true)
}
