import SwiftUI

/// Premium, highly polished license activation screen for LocSpoof.
struct LicenseView: View {
    @ObservedObject var licenseManager: LicenseManager
    @State private var inputKey: String = ""
    @State private var isActivating = false
    @State private var showSuccess = false
    @State private var shake = false
    @State private var ringRotation: Double = 0
    @State private var animateOrbs = false
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            // MARK: - Background Gradient with Drifting Orbs
            backgroundView

            VStack(spacing: 0) {
                Spacer()

                // MARK: - Logo & Title Header
                headerSection
                    .padding(.bottom, 32)

                // MARK: - License Input Card
                inputCardSection
                    .frame(maxWidth: 460)

                Spacer()

                // MARK: - Footer
                footerSection
            }

            // MARK: - Success Modal Overlay
            if showSuccess {
                successOverlayView
            }
        }
        .frame(minWidth: 650, minHeight: 600)
        .onAppear {
            withAnimation(.linear(duration: 16).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
                animateOrbs = true
            }
        }
    }

    // MARK: - Background View

    private var backgroundView: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.08)
                .ignoresSafeArea()

            // Glowing cyan orb
            Circle()
                .fill(Color.cyan.opacity(0.08))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(x: animateOrbs ? -120 : -180, y: animateOrbs ? -80 : -140)

            // Glowing purple orb
            Circle()
                .fill(Color.purple.opacity(0.07))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: animateOrbs ? 180 : 120, y: animateOrbs ? 140 : 80)

            // Subtle dark grid texture to represent map coordinates
            Path { path in
                let step: CGFloat = 40
                for x in stride(from: 0, to: 800, by: step) {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: 800))
                }
                for y in stride(from: 0, to: 800, by: step) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: 800, y: y))
                }
            }
            .stroke(Color.white.opacity(0.015), lineWidth: 1)
            .ignoresSafeArea()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 16) {
            ZStack {
                // Outer rotating gradient track
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            colors: [
                                Color.cyan,
                                Color.blue.opacity(0.3),
                                Color.purple,
                                Color.cyan
                            ],
                            center: .center
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 90, height: 90)
                    .rotationEffect(.degrees(ringRotation))

                // Outer soft glow
                Circle()
                    .fill(Color.cyan.opacity(0.12))
                    .frame(width: 104, height: 104)
                    .blur(radius: 6)

                // Vector app icon representation
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.12, green: 0.12, blue: 0.2), Color(red: 0.05, green: 0.05, blue: 0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 76, height: 76)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(.white.opacity(0.12), lineWidth: 1.5)
                        )
                        .shadow(color: .black.opacity(0.5), radius: 10, y: 5)

                    // Map pin vector representation
                    Image(systemName: "location.fill.viewfinder")
                        .font(.system(size: 32, weight: .regular))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.cyan, .blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .cyan.opacity(0.5), radius: 8)
                }
            }

            VStack(spacing: 4) {
                Text("LocSpoof")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Text("GPS Simulation & Protection Suite")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    // MARK: - Input Card Section

    private var inputCardSection: some View {
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                Text("Enter License Key")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)

                Text("Activation requires a valid cryptographic key")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }

            // Input field
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(isFocused ? Color.cyan : Color.secondary)

                    TextField("XXXX-XXXX-XXXX-XXXX", text: $inputKey)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                        .foregroundStyle(.white)
                        .focused($isFocused)
                        .onChange(of: inputKey) { oldValue, newValue in
                            inputKey = formatKeyInput(newValue)
                            licenseManager.validationError = nil
                        }
                        .onSubmit {
                            activateKey()
                        }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    isFocused ? Color.cyan.opacity(0.4) : .white.opacity(0.08),
                                    lineWidth: 1.5
                                )
                        )
                )
                .shadow(color: isFocused ? Color.cyan.opacity(0.08) : .clear, radius: 10)

                // Error text block
                if let error = licenseManager.validationError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                        Text(error)
                            .font(.system(.caption, design: .rounded))
                    }
                    .foregroundStyle(.red.opacity(0.9))
                    .padding(.top, 2)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .modifier(ShakeEffect(shakes: shake ? 2 : 0))
            .animation(.default, value: shake)

            // Submit Button
            Button {
                activateKey()
            } label: {
                HStack(spacing: 8) {
                    if isActivating {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14, weight: .bold))
                    }

                    Text(isActivating ? "Verifying..." : "Activate Software")
                        .font(.system(.body, design: .rounded, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    LinearGradient(
                        colors: inputKey.isEmpty
                            ? [.gray.opacity(0.2), .gray.opacity(0.15)]
                            : [Color.cyan, Color.blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .shadow(color: inputKey.isEmpty ? .clear : Color.cyan.opacity(0.2), radius: 10, y: 4)
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(inputKey.isEmpty || isActivating)

            // Dynamic horizontal divider
            HStack {
                Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                Text("OR")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.25))
                Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            }
            .padding(.vertical, 4)

            HStack(spacing: 12) {
                // TRY Button
                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                        licenseManager.startTrial()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.circle.fill")
                        Text("TRY TRIAL")
                    }
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .foregroundStyle(.cyan)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.cyan.opacity(0.25), lineWidth: 1.2)
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                
                // BUY Button
                Link(destination: URL(string: "https://pyrollc.com.tr/locspoof")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "cart.fill")
                        Text("BUY KEY")
                    }
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1.2)
                    )
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding(32)
        .background(
            ZStack {
                // Glass card body
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)

                // Card edge highlights
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.12), .white.opacity(0.04), .white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(0.4), radius: 30, y: 15)
        .padding(.horizontal, 24)
    }


    // MARK: - Success Overlay View

    private var successOverlayView: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 84, height: 84)

                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                        .shadow(color: .green.opacity(0.5), radius: 10)
                }

                VStack(spacing: 6) {
                    Text("License Verified")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Unlocking GPS Spoofing & Protection Suite")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.5), radius: 40)
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
        .transition(.opacity)
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        VStack(spacing: 4) {
            Text("LocSpoof Activation Center")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.2))
            
            Text("© 2026 LocSpoof Software. All rights reserved.")
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(.white.opacity(0.15))
        }
        .padding(.bottom, 24)
    }

    // MARK: - Activation Logic

    private func activateKey() {
        guard !inputKey.isEmpty else { return }
        isActivating = true

        Task {
            let success = await licenseManager.activate(with: inputKey)
            await MainActor.run {
                isActivating = false

                if success {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) {
                        showSuccess = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        withAnimation(.easeOut(duration: 0.35)) {
                            showSuccess = false
                        }
                    }
                } else {
                    withAnimation(.default) {
                        shake.toggle()
                    }
                }
            }
        }
    }

    private func formatKeyInput(_ input: String) -> String {
        let cleaned = input.uppercased().filter { $0.isLetter || $0.isNumber }
        let limited = String(cleaned.prefix(16))
        var result = ""
        for (i, char) in limited.enumerated() {
            if i > 0 && i % 4 == 0 { result += "-" }
            result.append(char)
        }
        return result
    }
}

// MARK: - Shake Effect

struct ShakeEffect: GeometryEffect {
    var position: CGFloat
    var animatableData: CGFloat {
        get { position }
        set { position = newValue }
    }

    init(shakes: Int) {
        position = CGFloat(shakes)
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: sin(position * .pi * 3) * 8, y: 0))
    }
}

#Preview {
    LicenseView(licenseManager: .shared)
        .frame(width: 650, height: 600)
}
