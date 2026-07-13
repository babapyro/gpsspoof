import SwiftUI
import MapKit

struct ContentView: View {
    @EnvironmentObject var deviceManager: DeviceSpoofManager
    @EnvironmentObject var mapVM: MapViewModel
    @ObservedObject private var dependencyManager = DependencyManager.shared
    @ObservedObject private var licenseManager = LicenseManager.shared

    @State private var showSidebar = true
    @State private var mapLoaded = false

    /// Whether the car icon should be shown (during route/GPX simulation)
    private var isFollowingRoute: Bool {
        deviceManager.simulationMode == .routeSimulation || deviceManager.simulationMode == .gpxPlayback
    }

    var body: some View {
        ZStack {
            if dependencyManager.hasDependencies {
                HStack(spacing: 0) {
                    // MARK: - Sidebar
                    if showSidebar {
                        DeviceSidebarView()
                            .frame(width: 290)
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity).animation(.spring(response: 0.45, dampingFraction: 0.82)),
                                removal: .move(edge: .leading).combined(with: .opacity).animation(.spring(response: 0.35, dampingFraction: 0.9))
                            ))

                        // Subtle divider glow
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.clear, Color.accentColor.opacity(0.15), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 1)
                            .shadow(color: Color.accentColor.opacity(0.2), radius: 4)
                    }

                    // MARK: - Main Map Area
                    ZStack(alignment: .topLeading) {
                        mapContent
                            .opacity(mapLoaded ? 1 : 0)
                            .animation(.easeOut(duration: 0.6), value: mapLoaded)

                        // Dark gradient overlays for floating controls readability
                        VStack(spacing: 0) {
                            LinearGradient(
                                colors: [.black.opacity(0.25), .black.opacity(0.08), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 80)
                            .allowsHitTesting(false)

                            Spacer()

                            LinearGradient(
                                colors: [.clear, .black.opacity(0.06), .black.opacity(0.2)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 120)
                            .allowsHitTesting(false)
                        }

                        // Floating controls overlay
                        VStack(spacing: 0) {
                            // Top bar
                            HStack(spacing: 12) {
                                sidebarToggleButton
                                SearchBarView()
                                Spacer()
                                StatusBarView()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)

                            Spacer()

                            // Bottom bar
                            HStack(alignment: .bottom, spacing: 16) {
                                ControlPanelView()

                                Spacer()

                                if mapVM.showJoystick {
                                    JoystickView()
                                        .transition(.asymmetric(
                                            insertion: .scale(scale: 0.5, anchor: .bottomTrailing)
                                                .combined(with: .opacity)
                                                .animation(.spring(response: 0.5, dampingFraction: 0.72)),
                                            removal: .scale(scale: 0.6, anchor: .bottomTrailing)
                                                .combined(with: .opacity)
                                                .animation(.easeIn(duration: 0.2))
                                        ))
                                }
                            }
                            .padding(16)
                        }
                    }
                }
                .background(Color(nsColor: .windowBackgroundColor))
                .onChange(of: deviceManager.currentSpoofedLocation) { oldValue, newLocation in
                    if let newLocation = newLocation {
                        if deviceManager.simulationMode == .routeSimulation || deviceManager.simulationMode == .gpxPlayback {
                            let headingDegrees = deviceManager.currentHeading * 180 / .pi
                            withAnimation(.easeInOut(duration: 0.25)) {
                                mapVM.cameraPosition = .camera(MapCamera(
                                    centerCoordinate: newLocation,
                                    distance: 500,
                                    heading: headingDegrees,
                                    pitch: 50
                                ))
                            }
                        }
                    }
                }
            } else {
                dependencySetupView
                    .transition(.opacity)
            }

            // MARK: - Ad Popup Overlay
            adOverlay

            // MARK: - Pro Paywall Overlay
            proPaywallOverlay
        }
        .onAppear {
            Task {
                let satisfied = await dependencyManager.checkDependencies()
                if satisfied {
                    deviceManager.scanForDevices()
                    withAnimation(.easeOut(duration: 0.5).delay(0.15)) {
                        mapLoaded = true
                    }
                } else {
                    // Try to install dependencies automatically in the background
                    await dependencyManager.installDependencies()
                    if dependencyManager.hasDependencies {
                        deviceManager.scanForDevices()
                        withAnimation(.easeOut(duration: 0.5).delay(0.15)) {
                            mapLoaded = true
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sidebar Toggle

    private var sidebarToggleButton: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                showSidebar.toggle()
            }
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Map Content

    @ViewBuilder
    private var mapContent: some View {
        MapReader { proxy in
            Map(position: $mapVM.cameraPosition, interactionModes: .all) {
                // Selected pin
                if let coord = mapVM.selectedCoordinate {
                    Annotation("Selected", coordinate: coord) {
                        DropPinView()
                    }
                }

                // Waypoints
                ForEach(mapVM.waypoints) { wp in
                    Annotation("Point \(wp.index + 1)", coordinate: wp.coordinate) {
                        WaypointPinView(index: wp.index + 1)
                    }
                }

                // Current spoofed/simulated location
                if let spoofed = deviceManager.currentSpoofedLocation {
                    Annotation("Current", coordinate: spoofed) {
                        if isFollowingRoute {
                            RouteCarView(heading: deviceManager.currentHeading)
                        } else {
                            SpoofedLocationView()
                        }
                    }
                }

                // Route polyline
                if !mapVM.routeCoordinates.isEmpty {
                    MapPolyline(coordinates: mapVM.routeCoordinates)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.35, green: 0.5, blue: 1.0),
                                    Color(red: 0.2, green: 0.8, blue: 0.9),
                                    Color(red: 0.3, green: 0.9, blue: 0.7)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                        )
                }
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .automatic, pointsOfInterest: .all, showsTraffic: false))
            .mapControls {
                MapCompass()
                MapScaleView()
                MapZoomStepper()
            }
            .onTapGesture { screenCoord in
                if let coordinate = proxy.convert(screenCoord, from: .local) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        mapVM.handleMapTap(at: coordinate)
                    }
                }
            }
        }
    }
}

// MARK: - Custom Button Styles

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

struct GlowButtonStyle: ButtonStyle {
    var color: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .brightness(configuration.isPressed ? 0.1 : 0)
            .shadow(color: color.opacity(configuration.isPressed ? 0.5 : 0), radius: 12)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Pin Views

struct DropPinView: View {
    @State private var dropped = false
    @State private var ringPulse = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .strokeBorder(Color.red.opacity(0.3 - Double(i) * 0.1), lineWidth: 1.5)
                    .frame(width: 50, height: 50)
                    .scaleEffect(ringPulse ? 1.0 + CGFloat(i) * 0.3 : 0.5)
                    .opacity(ringPulse ? 0 : 0.6)
            }

            Ellipse()
                .fill(.black.opacity(0.2))
                .frame(width: 16, height: 6)
                .offset(y: 12)
                .blur(radius: 2)
                .scaleEffect(dropped ? 1 : 0.4)

            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(red: 1, green: 0.35, blue: 0.35), .red],
                                center: .init(x: 0.35, y: 0.35),
                                startRadius: 0,
                                endRadius: 12
                            )
                        )
                        .frame(width: 22, height: 22)
                        .shadow(color: .red.opacity(0.5), radius: 8, y: 3)

                    Circle()
                        .fill(.white.opacity(0.9))
                        .frame(width: 7, height: 7)
                }

                Triangle()
                    .fill(.red)
                    .frame(width: 10, height: 8)
                    .offset(y: -2)
            }
            .offset(y: dropped ? 0 : -20)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { dropped = true }
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: false).delay(0.3)) { ringPulse = true }
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.closeSubpath()
        }
    }
}

struct WaypointPinView: View {
    let index: Int
    @State private var appeared = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.indigo.opacity(0.2))
                .frame(width: 36, height: 36)
                .blur(radius: 4)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.45, green: 0.35, blue: 1.0), Color(red: 0.3, green: 0.2, blue: 0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
                .shadow(color: .indigo.opacity(0.5), radius: 6, y: 2)

            Text("\(index)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .scaleEffect(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { appeared = true }
        }
    }
}

// MARK: - Spoofed Location (Teleport / Joystick)

struct SpoofedLocationView: View {
    @State private var ring1 = false
    @State private var ring2 = false
    @State private var glow = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.cyan.opacity(0.3), lineWidth: 1.5)
                .frame(width: 50, height: 50)
                .scaleEffect(ring1 ? 1.6 : 0.8)
                .opacity(ring1 ? 0 : 0.5)

            Circle()
                .strokeBorder(Color.blue.opacity(0.25), lineWidth: 1.5)
                .frame(width: 50, height: 50)
                .scaleEffect(ring2 ? 1.4 : 0.8)
                .opacity(ring2 ? 0 : 0.5)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.cyan.opacity(0.25), .clear],
                        center: .center,
                        startRadius: 5,
                        endRadius: 25
                    )
                )
                .frame(width: 50, height: 50)
                .scaleEffect(glow ? 1.15 : 0.9)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white, Color(red: 0.2, green: 0.6, blue: 1.0), Color(red: 0.15, green: 0.4, blue: 0.95)],
                        center: .init(x: 0.4, y: 0.35),
                        startRadius: 0,
                        endRadius: 11
                    )
                )
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                .shadow(color: .blue.opacity(0.6), radius: 8, y: 1)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: false)) { ring1 = true }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: false).delay(0.7)) { ring2 = true }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { glow = true }
        }
    }
}

// MARK: - Route Car View (Following Route)

struct RouteCarView: View {
    let heading: Double  // radians, 0 = North
    @State private var trailPulse = false
    @State private var appeared = false

    /// Convert bearing (radians, 0=North clockwise) to SwiftUI rotation (0=right, counter-clockwise)
    private var rotationDegrees: Double {
        heading * 180 / .pi
    }

    var body: some View {
        ZStack {
            // Directional glow trail (behind the car)
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [Color.blue.opacity(0.25), .clear],
                        center: .center,
                        startRadius: 2,
                        endRadius: 22
                    )
                )
                .frame(width: 44, height: 44)
                .scaleEffect(trailPulse ? 1.2 : 0.9)
                .opacity(trailPulse ? 0.4 : 0.8)

            // Car icon container
            ZStack {
                // Background circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.2, green: 0.5, blue: 1.0),
                                Color(red: 0.15, green: 0.35, blue: 0.9)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 34, height: 34)
                    .shadow(color: .blue.opacity(0.5), radius: 8, y: 2)

                // Border
                Circle()
                    .strokeBorder(.white, lineWidth: 2.5)
                    .frame(width: 34, height: 34)

                // Car icon — rotated to match heading
                Image(systemName: "car.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(rotationDegrees))
                    .animation(.easeInOut(duration: 0.3), value: heading)
            }

            // Direction indicator arrow (pointing forward)
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.8))
                .offset(y: -24)
                .rotationEffect(.degrees(rotationDegrees))
                .animation(.easeInOut(duration: 0.3), value: heading)
        }
        .scaleEffect(appeared ? 1 : 0.3)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) {
                appeared = true
            }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                trailPulse = true
            }
        }
    }
}

extension ContentView {
    // MARK: - Advert Overlay for Trial Mode
    @ViewBuilder
    private var adOverlay: some View {
        if deviceManager.showAdPopup {
            ZStack {
                Color.black.opacity(0.65)
                    .ignoresSafeArea()
                    .transition(.opacity)
                
                VStack(spacing: 24) {
                    // Header Promo
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.15))
                                .frame(width: 60, height: 60)
                            
                            Image(systemName: "crown.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.yellow, .orange],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: .orange.opacity(0.5), radius: 6)
                        }
                        
                        Text("LocSpoof Premium Edition")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        
                        Text("Unlock maximum capability and anti-detection systems")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    
                    // Promo Feature List
                    VStack(alignment: .leading, spacing: 14) {
                        PromoFeatureRow(icon: "shield.fill", iconColor: .green, title: "Snapchat Safe Guard", desc: "Prevents Snap Map detection, velocity flags, and device bans.")
                        PromoFeatureRow(icon: "play.circle.fill", iconColor: .cyan, title: "Ultra-Smooth Routing", desc: "4x increase in location coordinate update resolution.")
                        PromoFeatureRow(icon: "arrow.triangle.swap", iconColor: .blue, title: "Waypoint Simulation", desc: "Build unlimited points routes and playback GPX paths.")
                        PromoFeatureRow(icon: "dpad.fill", iconColor: .purple, title: "Virtual Joystick", desc: "Control manual movement fluidly with keyboard/D-pad.")
                        PromoFeatureRow(icon: "gauge.with.needle", iconColor: .orange, title: "Extreme Speed Limits", desc: "Simulate real vehicle driving speeds up to 275 km/h.")
                    }
                    .padding(.horizontal, 16)
                    
                    // Buttons
                    VStack(spacing: 10) {
                        // Redirect / Buy Button
                        Button {
                            if let url = URL(string: "https://pyrollc.com.tr/locspoof") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "cart.fill")
                                Text("Get Premium License Key")
                            }
                            .font(.system(.body, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(
                                    colors: [.orange, Color(red: 0.9, green: 0.4, blue: 0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .shadow(color: .orange.opacity(0.3), radius: 8, y: 3)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        
                        // Proceed Button
                        Button {
                            withAnimation(.easeOut(duration: 0.25)) {
                                deviceManager.showAdPopup = false
                                // Run the pending spoof action
                                deviceManager.pendingSpoofAction?()
                                deviceManager.pendingSpoofAction = nil
                            }
                        } label: {
                            Text("Continue with Free Trial")
                                .font(.system(.caption, design: .rounded, weight: .bold))
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                                )
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
                .padding(32)
                .frame(width: 440)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                        )
                )
                .shadow(color: .black.opacity(0.5), radius: 40)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
            .transition(.opacity)
        }
    }
}

struct PromoFeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let desc: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 28, height: 28)
                
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(iconColor)
            }
            .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                
                Text(desc)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(2)
            }
        }
    }
}

extension ContentView {
    // MARK: - Onboarding Dependency Setup View
    @ViewBuilder
    private var dependencySetupView: some View {
        ZStack {
            // Dark futuristic backdrop
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 28) {
                // Glow logo
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.accentColor)
                        .symbolEffect(.pulse, options: .repeating)
                }
                
                VStack(spacing: 8) {
                    Text("LocSpoof Environment Setup")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Text("Configuring macOS drivers and toolchains for physical spoofing")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                
                // Progress block
                VStack(spacing: 12) {
                    ProgressView(value: dependencyManager.progress)
                        .tint(Color.accentColor)
                        .frame(width: 320)
                    
                    Text(dependencyManager.statusMessage)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.accentColor.opacity(0.8))
                }
                .padding(.vertical, 8)
                
                // Error Alert Box
                if let err = dependencyManager.installationError {
                    VStack(spacing: 12) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .font(.system(size: 16))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Setup Failed")
                                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                                    .foregroundStyle(.white)
                                
                                Text(err)
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .lineLimit(5)
                            }
                        }
                        .padding(16)
                        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.red.opacity(0.2), lineWidth: 1)
                        )
                        .frame(width: 380)
                        
                        Button {
                            Task {
                                await dependencyManager.installDependencies()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Retry Installation")
                            }
                            .font(.system(.body, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(white: 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.6), radius: 40)
        }
    }

    // MARK: - Pro Upgrade Modal Overlay
    @ViewBuilder
    private var proPaywallOverlay: some View {
        if licenseManager.showProPaywall {
            ZStack {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .transition(.opacity)
                
                ProPaywallView()
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
    }
}

struct ProPaywallView: View {
    @ObservedObject private var licenseManager = LicenseManager.shared
    @State private var inputKey = ""
    @State private var isActivating = false
    @State private var shake = false

    var body: some View {
        VStack(spacing: 24) {
            // Crown badge
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.yellow.opacity(0.15))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: "crown.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .orange.opacity(0.4), radius: 6)
                }
                
                Text("Upgrade to LocSpoof Pro")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                
                Text("Unlock premium device simulation controls")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
            
            // Feature list
            VStack(alignment: .leading, spacing: 12) {
                PaywallFeatureRow(icon: "point.topleft.down.to.point.bottomright.curvepath.fill", color: .orange, title: "Multi-Point Route Simulation", desc: "Draw complex routes with customized speeds up to 275 km/h.")
                PaywallFeatureRow(icon: "dpad.fill", color: .purple, title: "Virtual Joystick", desc: "Interact manually using keyboard D-pad controls for precision walking.")
                PaywallFeatureRow(icon: "doc.badge.plus", color: .teal, title: "GPX File Import & Playback", desc: "Replay real world tracking runs from standard GPX navigation files.")
            }
            .padding(.horizontal, 8)
            
            // Activation Block
            VStack(alignment: .leading, spacing: 8) {
                Text("Already have a key?")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                
                HStack(spacing: 8) {
                    TextField("XXXX-XXXX-XXXX-XXXX", text: $inputKey)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                        )
                        .frame(width: 220)
                    
                    Button {
                        activateKey()
                    } label: {
                        HStack {
                            if isActivating {
                                ProgressView().scaleEffect(0.6).tint(.white)
                            } else {
                                Text("Activate")
                            }
                        }
                        .font(.system(.body, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .disabled(inputKey.isEmpty || isActivating)
                }
                
                if let error = licenseManager.validationError {
                    Text(error)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.red)
                        .transition(.opacity)
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
            .modifier(ShakeEffect(shakes: shake ? 2 : 0))
            
            // Primary Actions
            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeOut(duration: 0.25)) {
                        licenseManager.showProPaywall = false
                    }
                } label: {
                    Text("Maybe Later")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                        )
                }
                .buttonStyle(ScaleButtonStyle())
                
                Button {
                    if let url = URL(string: "https://pyrollc.com.tr/locspoof") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "cart.fill")
                        Text("Buy Pro Key")
                    }
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(colors: [.orange, Color(red: 0.9, green: 0.4, blue: 0.15)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding(32)
        .frame(width: 440)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.5), radius: 40)
    }

    private func activateKey() {
        isActivating = true
        Task {
            let success = await licenseManager.activate(with: inputKey)
            await MainActor.run {
                isActivating = false
                if success {
                    withAnimation(.easeOut(duration: 0.25)) {
                        licenseManager.showProPaywall = false
                    }
                } else {
                    withAnimation(.default) {
                        shake = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        shake = false
                    }
                }
            }
        }
    }
}

struct PaywallFeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let desc: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(color.opacity(0.12)).frame(width: 28, height: 28)
                Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundStyle(color)
            }
            .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                
                Text(desc)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(2)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(DeviceSpoofManager.shared)
        .environmentObject(MapViewModel())
        .frame(width: 1200, height: 800)
}
