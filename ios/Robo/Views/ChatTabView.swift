import SwiftUI

struct ChatTabView: View {
    var body: some View {
        if #available(iOS 26, *) {
            FoundationModelsChatGate()
        } else {
            ChatUnavailableView(reason: .osNotSupported)
        }
    }
}

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26, *)
private struct FoundationModelsChatGate: View {
    var body: some View {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            ChatView()
        case .unavailable(.deviceNotEligible):
            ChatUnavailableView(reason: .hardwareNotSupported)
        case .unavailable(.appleIntelligenceNotEnabled):
            ChatUnavailableView(reason: .appleIntelligenceDisabled)
        case .unavailable(.modelNotReady):
            ChatUnavailableView(reason: .modelDownloading)
        default:
            ChatUnavailableView(reason: .unknown)
        }
    }
}
#endif
