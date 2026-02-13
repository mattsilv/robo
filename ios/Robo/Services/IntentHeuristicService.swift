import Foundation
import SwiftUI

/// Rule-based heuristic that maps a capture type + metadata to suggested agents.
/// Designed to be swapped for an AI model later without changing the routing UI.
enum IntentHeuristicService {

    struct SuggestedRoute: Identifiable {
        let id = UUID()
        let agentName: String
        let agentIcon: String
        let agentColor: Color
        let confidence: Double  // 0.0–1.0
        let reason: String
    }

    /// Returns agent suggestions based on what was just captured.
    static func suggest(for routing: CaptureRouting) -> [SuggestedRoute] {
        switch routing.sensorType {
        case .lidar:
            return [
                SuggestedRoute(
                    agentName: "Interior Designer",
                    agentIcon: "sofa",
                    agentColor: .purple,
                    confidence: 0.9,
                    reason: "Room scans are ideal for furniture layout and design"
                ),
                SuggestedRoute(
                    agentName: "Contractor Bot",
                    agentIcon: "hammer",
                    agentColor: .yellow,
                    confidence: 0.7,
                    reason: "Accurate measurements help with renovation estimates"
                )
            ]

        case .barcode:
            return [
                SuggestedRoute(
                    agentName: "Practical Chef",
                    agentIcon: "fork.knife",
                    agentColor: .orange,
                    confidence: 0.8,
                    reason: "Barcode scans can look up nutrition and recipe data"
                )
            ]

        case .productScan:
            return [
                SuggestedRoute(
                    agentName: "Practical Chef",
                    agentIcon: "fork.knife",
                    agentColor: .orange,
                    confidence: 0.9,
                    reason: "Product scans with photos enable full ingredient analysis"
                )
            ]

        case .camera:
            return cameraHeuristic(photoCount: routing.photoCount)

        case .motion, .health:
            // Motion and health data save locally by default
            return []

        case .beacon:
            return [
                SuggestedRoute(
                    agentName: "Home Aware",
                    agentIcon: "sensor.tag.radiowaves.forward",
                    agentColor: .indigo,
                    confidence: 0.9,
                    reason: "Beacon events enable room-based automations"
                )
            ]
        }
    }

    // MARK: - Camera Heuristics

    /// For photos, suggest agents based on photo count and patterns.
    /// A real implementation would use vision APIs for content detection.
    private static func cameraHeuristic(photoCount: Int) -> [SuggestedRoute] {
        if photoCount == 1 {
            // Single photo — could be selfie/portrait → Color Analyst
            return [
                SuggestedRoute(
                    agentName: "Color Analyst",
                    agentIcon: "paintpalette.fill",
                    agentColor: .pink,
                    confidence: 0.6,
                    reason: "Portrait photos can be analyzed for personalized color palettes"
                ),
                SuggestedRoute(
                    agentName: "Smart Stylist",
                    agentIcon: "tshirt",
                    agentColor: .cyan,
                    confidence: 0.5,
                    reason: "Single photos work for quick outfit feedback"
                )
            ]
        } else {
            // Multi-photo — could be wardrobe, store, flowers, etc.
            return [
                SuggestedRoute(
                    agentName: "Smart Stylist",
                    agentIcon: "tshirt",
                    agentColor: .cyan,
                    confidence: 0.6,
                    reason: "Multiple photos of clothing or spaces help plan outfits"
                ),
                SuggestedRoute(
                    agentName: "Florist",
                    agentIcon: "leaf.fill",
                    agentColor: .green,
                    confidence: 0.5,
                    reason: "Photos of flowers can be analyzed for arrangement suggestions"
                ),
                SuggestedRoute(
                    agentName: "Store Ops",
                    agentIcon: "building.2",
                    agentColor: .green,
                    confidence: 0.4,
                    reason: "Multi-photo sets work for compliance checklists"
                )
            ]
        }
    }
}
