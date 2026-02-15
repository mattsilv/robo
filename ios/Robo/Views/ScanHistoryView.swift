import SwiftUI
import SwiftData

struct ScanHistoryView: View {
    @Query(sort: \ScanRecord.capturedAt, order: .reverse)
    private var scans: [ScanRecord]
    @Query(sort: \RoomScanRecord.capturedAt, order: .reverse)
    private var roomScans: [RoomScanRecord]
    @Query(sort: \MotionRecord.capturedAt, order: .reverse)
    private var motionRecords: [MotionRecord]
@Query(sort: \BeaconEventRecord.capturedAt, order: .reverse)
    private var beaconEvents: [BeaconEventRecord]
    @Query(sort: \AgentCompletionRecord.completedAt, order: .reverse)
    private var agentCompletions: [AgentCompletionRecord]
    @Environment(\.modelContext) private var modelContext

    @State private var selectedSegment = 0
    @State private var showingClearConfirmation = false
    @State private var shareURL: URL?
    @State private var isExporting = false
    @State private var showingBarcodeScanner = false
    @State private var showingLiDARScanner = false
    @State private var showingMotionCapture = false
    @State private var showingBeaconMonitor = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Type", selection: $selectedSegment) {
                    Text("Barcodes").tag(0)
                    Text("Rooms").tag(1)
                    Text("Motion").tag(2)
                    Text("Beacons").tag(3)
                    Text("Tasks").tag(4)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                Spacer().frame(height: 8)

                Group {
                    switch selectedSegment {
                    case 0: barcodeList
                    case 1: roomList
                    case 2: motionList
                    case 3: beaconList
                    case 4: tasksList
                    default: barcodeList
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
                        .disabled(isExporting || (scans.isEmpty && roomScans.isEmpty && motionRecords.isEmpty && beaconEvents.isEmpty))
                    }

                    if (selectedSegment == 0 && !scans.isEmpty) ||
                       (selectedSegment == 1 && !roomScans.isEmpty) ||
                       (selectedSegment == 2 && !motionRecords.isEmpty) ||
                       (selectedSegment == 3 && !beaconEvents.isEmpty) ||
                       (selectedSegment == 4 && !agentCompletions.isEmpty) {
                        ToolbarItem(placement: .destructiveAction) {
                            Button("Clear All", role: .destructive) {
                                showingClearConfirmation = true
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
                case 4:
                    Text("This will permanently delete \(agentCompletions.count) task\(agentCompletions.count == 1 ? "" : "s").")
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
            .fullScreenCover(isPresented: $showingBeaconMonitor) {
                BeaconMonitorView()
            }
        }
    }

    // MARK: - Quick Capture Section

    @ViewBuilder
    private var quickCaptureSection: some View {
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
            Button { showingBeaconMonitor = true } label: {
                Label("Monitor Beacons", systemImage: "sensor.tag.radiowaves.forward")
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
                quickCaptureSection
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
                quickCaptureSection
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
                quickCaptureSection
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
            } actions: {
                Button("Monitor Beacons") {
                    showingBeaconMonitor = true
                }
            }
        } else {
            List {
                // Summary visualization
                Section {
                    BeaconSummaryCard(events: beaconEvents)
                }

                // Timeline
                Section("Event Timeline") {
                    BeaconTimelineView(events: beaconEvents)
                }

                // Event list
                Section("All Events (\(beaconEvents.count))") {
                    ForEach(beaconEvents) { event in
                        BeaconEventRow(event: event)
                    }
                    .onDelete(perform: deleteBeaconEvents)
                }

                quickCaptureSection
            }
        }
    }

    // MARK: - Tasks List

    @ViewBuilder
    private var tasksList: some View {
        if agentCompletions.isEmpty {
            ContentUnavailableView {
                Label("No Tasks Yet", systemImage: "checklist")
            } description: {
                Text("Completed agent tasks will appear here.")
            }
        } else {
            List {
                ForEach(agentCompletions) { completion in
                    AgentCompletionRow(completion: completion)
                }
                .onDelete(perform: deleteCompletions)
            }
        }
    }

    private func deleteCompletions(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(agentCompletions[index])
        }
        try? modelContext.save()
    }

    // MARK: - Export All Section

    private var totalItemCount: Int {
        scans.count + roomScans.count + motionRecords.count + beaconEvents.count + agentCompletions.count
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
        case 4:
            for completion in agentCompletions { modelContext.delete(completion) }
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
        let beaconData = beaconEvents.map {
            ExportableBeaconEvent(eventType: $0.eventType, beaconMinor: $0.beaconMinor, roomName: $0.roomName, proximity: $0.proximity, rssi: $0.rssi, distanceMeters: $0.distanceMeters, durationSeconds: $0.durationSeconds, source: $0.source, webhookStatus: $0.webhookStatus, capturedAt: $0.capturedAt)
        }
        Task.detached {
            do {
                let url = try ExportService.createCombinedExportZip(
                    scans: barcodeData,
                    rooms: roomData,
                    motionRecords: motionData,
                    beaconEvents: beaconData
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

// MARK: - Beacon Summary Card

struct BeaconSummaryCard: View {
    let events: [BeaconEventRecord]

    private var enterCount: Int { events.filter { $0.eventType == "enter" }.count }
    private var exitCount: Int { events.filter { $0.eventType == "exit" }.count }

    private var roomVisits: [(name: String, count: Int)] {
        let enters = events.filter { $0.eventType == "enter" }
        let grouped = Dictionary(grouping: enters) { $0.roomName ?? "Beacon \($0.beaconMinor)" }
        return grouped.map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    private var avgDuration: Int? {
        let durations = events.compactMap { $0.durationSeconds }
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / durations.count
    }

    var body: some View {
        VStack(spacing: 12) {
            // Stats row
            HStack(spacing: 0) {
                statCell(value: "\(enterCount)", label: "Enters", color: .green)
                Divider().frame(height: 32)
                statCell(value: "\(exitCount)", label: "Exits", color: .orange)
                Divider().frame(height: 32)
                if let avg = avgDuration {
                    statCell(value: formatDuration(avg), label: "Avg Stay", color: .blue)
                } else {
                    statCell(value: "\(roomVisits.count)", label: "Zones", color: .blue)
                }
            }

            // Room breakdown bars
            if !roomVisits.isEmpty {
                let maxCount = roomVisits.first?.count ?? 1
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(roomVisits.prefix(4), id: \.name) { room in
                        HStack(spacing: 8) {
                            Text(room.name)
                                .font(.caption)
                                .frame(width: 80, alignment: .trailing)
                                .lineLimit(1)

                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.indigo.opacity(0.7))
                                    .frame(width: max(4, geo.size.width * CGFloat(room.count) / CGFloat(maxCount)))
                            }
                            .frame(height: 16)

                            Text("\(room.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .leading)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func statCell(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainMins = minutes % 60
        return "\(hours)h\(remainMins)m"
    }
}

// MARK: - Beacon Timeline View

struct BeaconTimelineView: View {
    let events: [BeaconEventRecord]

    private var recentEvents: [BeaconEventRecord] {
        Array(events.prefix(10))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(recentEvents.enumerated()), id: \.element.id) { index, event in
                HStack(alignment: .top, spacing: 12) {
                    // Timeline dot + line
                    VStack(spacing: 0) {
                        Circle()
                            .fill(event.eventType == "enter" ? Color.green : Color.orange)
                            .frame(width: 10, height: 10)

                        if index < recentEvents.count - 1 {
                            Rectangle()
                                .fill(.quaternary)
                                .frame(width: 2)
                                .frame(minHeight: 28)
                        }
                    }

                    // Event info
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(event.eventType == "enter" ? "Entered" : "Exited")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(event.eventType == "enter" ? .green : .orange)
                            Text(event.roomName ?? "Beacon \(event.beaconMinor)")
                                .font(.caption.weight(.medium))
                        }

                        HStack(spacing: 6) {
                            Text(event.capturedAt, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            if let duration = event.durationSeconds, duration > 0 {
                                Text("(\(formatDuration(duration)))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.bottom, 6)
                }
            }

            if events.count > 10 {
                Text("+\(events.count - 10) more events")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 22)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainMins = minutes % 60
        return "\(hours)h\(remainMins)m"
    }
}

// MARK: - Agent Completion Row

struct AgentCompletionRow: View {
    let completion: AgentCompletionRecord
    @State private var thumbnails: [UIImage] = []

    private var skillIcon: String {
        switch completion.skillType {
        case "camera": return "camera.fill"
        case "lidar": return "camera.metering.spot"
        case "barcode": return "barcode.viewfinder"
        case "beacon": return "sensor.tag.radiowaves.forward"
        default: return "checkmark.circle"
        }
    }

    private var skillColor: Color {
        switch completion.skillType {
        case "camera": return .blue
        case "lidar": return .purple
        case "barcode": return .orange
        case "beacon": return .indigo
        default: return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: skillIcon)
                    .font(.title2)
                    .foregroundStyle(skillColor)
                    .frame(width: 40, height: 40)
                    .background(skillColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(completion.agentName)
                        .font(.headline)
                    HStack(spacing: 8) {
                        Text(completion.skillType.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(skillColor.opacity(0.15))
                            .foregroundStyle(skillColor)
                            .clipShape(Capsule())
                        Text("\(completion.itemCount) item\(completion.itemCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(completion.completedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Photo thumbnails grid
            if !thumbnails.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(thumbnails.prefix(6).enumerated()), id: \.offset) { _, thumb in
                            Image(uiImage: thumb)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }

            // Album URL link
            if let urlStr = completion.albumURL, let url = URL(string: urlStr) {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                        Text("View Album")
                            .font(.subheadline)
                    }
                    .foregroundStyle(.blue)
                }
            }
        }
        .padding(.vertical, 4)
        .task {
            loadThumbnails()
        }
    }

    private func loadThumbnails() {
        let filenames = completion.photoFilenames
        guard !filenames.isEmpty else { return }
        var loaded: [UIImage] = []
        for name in filenames.prefix(6) {
            if let img = PhotoStorageService.loadThumbnail(name) {
                loaded.append(img)
            }
        }
        thumbnails = loaded
    }
}

#Preview {
    ScanHistoryView()
        .modelContainer(for: [ScanRecord.self, RoomScanRecord.self, MotionRecord.self, BeaconEventRecord.self, AgentCompletionRecord.self], inMemory: true)
}
