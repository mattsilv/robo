import SwiftUI

struct OnboardingView: View {
    @AppStorage("userName") private var userName = ""
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var nameInput = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(red: 0.02, green: 0.02, blue: 0.04), Color(red: 0.05, green: 0.05, blue: 0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: 20)

                    // App icon
                    if let uiImage = UIImage(named: "Icon-1024") {
                        Image(uiImage: uiImage)
                            .resizable()
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .shadow(color: .blue.opacity(0.3), radius: 20, y: 8)
                            .padding(.bottom, 24)
                    } else {
                        Image(systemName: "cpu")
                            .font(.system(size: 48))
                            .foregroundStyle(.blue)
                            .frame(width: 80, height: 80)
                            .background(Color.blue.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .padding(.bottom, 24)
                    }

                    // Wordmark
                    HStack(spacing: 0) {
                        Text("ROBO")
                            .font(.system(size: 32, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.white)
                        Text(".")
                            .font(.system(size: 32, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.blue)
                        Text("APP")
                            .font(.system(size: 32, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .padding(.bottom, 12)

                    // Tagline
                    Text("The Context Collector")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.blue)
                        .textCase(.uppercase)
                        .tracking(2)
                        .padding(.bottom, 24)

                    // Description
                    Text("Your phone has incredible sensors. Robo collects what they see — for you, for your team, or for your AI agent.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 40)

                    // Feature pills
                    VStack(spacing: 12) {
                        featureRow(icon: "cube.transparent", text: "LiDAR room scanning with measurements", color: .purple)
                        featureRow(icon: "camera.fill", text: "Photo capture for AI analysis", color: .blue)
                        featureRow(icon: "barcode.viewfinder", text: "Barcode & product scanning", color: .orange)
                        featureRow(icon: "person.3.fill", text: "Group decisions via shareable links", color: .green)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 48)

                    // Name input section
                    VStack(spacing: 16) {
                        Text("What's your first name?")
                            .font(.headline)
                            .foregroundStyle(.white)

                        TextField("", text: $nameInput, prompt: Text("First name").foregroundStyle(.white.opacity(0.4)))
                            .font(.title3)
                            .multilineTextAlignment(.center)
                            .padding(16)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                            .foregroundStyle(.white)
                            .focused($isNameFocused)
                            .submitLabel(.done)
                            .onSubmit { completeOnboarding() }
                            .padding(.horizontal, 40)
                    }
                    .id("nameInput")
                    .padding(.bottom, 24)
                    .onChange(of: isNameFocused) { _, focused in
                        if focused {
                            withAnimation {
                                proxy.scrollTo("nameInput", anchor: .center)
                            }
                        }
                    }

                    // CTA button
                    Button(action: completeOnboarding) {
                        Text("Get Started")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                nameInput.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? Color.blue.opacity(0.3)
                                    : Color.blue
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(nameInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 60)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            } // ScrollViewReader
        }
        .onTapGesture {
            isNameFocused = false
        }
    }

    private func featureRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func completeOnboarding() {
        let trimmed = nameInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        userName = trimmed
        withAnimation(.easeInOut(duration: 0.3)) {
            hasOnboarded = true
        }
    }
}

#Preview {
    OnboardingView()
}
