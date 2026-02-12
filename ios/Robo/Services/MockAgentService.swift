import Foundation
import SwiftUI

enum MockAgentService {
    static func loadAgents() -> [AgentConnection] {
        [
            AgentConnection(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                name: "Interior Designer",
                description: "AI-powered room design and furniture placement",
                iconSystemName: "sofa",
                accentColor: .purple,
                status: .connected,
                lastSyncDate: nil,
                pendingRequest: AgentRequest(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
                    title: "Send me the floor plan of your master bedroom",
                    description: "I'll use LiDAR measurements to suggest furniture layouts that actually fit.",
                    skillType: .lidar,
                    roomNameHint: "Master Bedroom"
                )
            ),
            AgentConnection(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                name: "Practical Chef",
                description: "Analyzes ingredients and nutrition for meal planning",
                iconSystemName: "fork.knife",
                accentColor: .orange,
                status: .connected,
                lastSyncDate: nil,
                pendingRequest: AgentRequest(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!,
                    title: "Scan a product from your kitchen",
                    description: "Scan the barcode and snap a few photos of the package — I'll analyze the ingredients and nutrition.",
                    skillType: .productScan,
                    photoChecklist: [
                        PhotoTask(id: UUID(), label: "Front of package", isCompleted: false),
                        PhotoTask(id: UUID(), label: "Nutrition label", isCompleted: false)
                    ]
                )
            ),
            AgentConnection(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                name: "Smart Stylist",
                description: "Outfit picks based on weather, calendar, and your wardrobe",
                iconSystemName: "tshirt",
                accentColor: .cyan,
                status: .connected,
                lastSyncDate: nil,
                pendingRequest: AgentRequest(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000030")!,
                    title: "Photo your closet",
                    description: "Snap your wardrobe — I'll suggest outfits based on weather, your calendar, and what actually fits.",
                    skillType: .camera,
                    photoChecklist: [
                        PhotoTask(id: UUID(), label: "Tops / shirts", isCompleted: false),
                        PhotoTask(id: UUID(), label: "Pants / skirts", isCompleted: false),
                        PhotoTask(id: UUID(), label: "Shoes", isCompleted: false),
                        PhotoTask(id: UUID(), label: "Accessories", isCompleted: false)
                    ]
                )
            ),
            AgentConnection(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!,
                name: "Home Aware",
                description: "Room-aware automations triggered by your location",
                iconSystemName: "sensor.tag.radiowaves.forward",
                accentColor: .indigo,
                status: .connected,
                lastSyncDate: nil,
                pendingRequest: AgentRequest(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000070")!,
                    title: "Set up beacon monitoring",
                    description: "Place beacons in your rooms and I'll track your movement patterns to automate reminders.",
                    skillType: .beacon
                )
            ),
            AgentConnection(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
                name: "Contractor Bot",
                description: "Send your contractor exactly what they need, first try",
                iconSystemName: "hammer",
                accentColor: .yellow,
                status: .connected,
                lastSyncDate: Calendar.current.date(byAdding: .minute, value: -30, to: Date()),
                pendingRequest: nil
            ),
            AgentConnection(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
                name: "Playtime Muse",
                description: "Creative activities based on your kids' ages and what's around",
                iconSystemName: "figure.and.child.holdinghands",
                accentColor: .pink,
                status: .connected,
                lastSyncDate: nil,
                pendingRequest: AgentRequest(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000050")!,
                    title: "Snap the playroom",
                    description: "Take photos — toys, bookshelves, craft supplies. I'll suggest activities for Emma (4) and Liam (7).",
                    skillType: .camera,
                    photoChecklist: [
                        PhotoTask(id: UUID(), label: "Toy shelves / bins", isCompleted: false),
                        PhotoTask(id: UUID(), label: "Books & games", isCompleted: false),
                        PhotoTask(id: UUID(), label: "Art & craft supplies", isCompleted: false),
                        PhotoTask(id: UUID(), label: "Open floor space", isCompleted: false)
                    ]
                )
            ),
            AgentConnection(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
                name: "Store Ops",
                description: "Scheduled photo checklists for business compliance",
                iconSystemName: "building.2",
                accentColor: .green,
                status: .connected,
                lastSyncDate: Calendar.current.date(byAdding: .hour, value: -1, to: Date()),
                pendingRequest: AgentRequest(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000060")!,
                    title: "Friday closing checklist",
                    description: "Time for your weekly closing photos — kitchen, displays, safe area. Takes 2 minutes.",
                    skillType: .camera,
                    photoChecklist: [
                        PhotoTask(id: UUID(), label: "Clean kitchen", isCompleted: false),
                        PhotoTask(id: UUID(), label: "Organized displays", isCompleted: false),
                        PhotoTask(id: UUID(), label: "Locked safe area", isCompleted: false)
                    ]
                )
            )
        ]
    }
}
