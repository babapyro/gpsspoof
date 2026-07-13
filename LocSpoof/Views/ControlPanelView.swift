import SwiftUI

struct ControlPanelView: View {
    @EnvironmentObject var deviceManager: DeviceSpoofManager
    @EnvironmentObject var mapVM: MapViewModel

    @State private var isExpanded = true
    @State private var teleportPulse = false
    @State private var routeProgress: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 24, height: 24)

                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                Text("Controls")
                    .font(.system(.headline, design: .rounded, weight: .bold))

                Spacer()

                // Mode badge
                if deviceManager.simulationMode != .idle {
                    SimulationBadge(mode: deviceManager.simulationMode)
                        .transition(.scale.combined(with: .opacity))
                }

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(.quaternary.opacity(0.4), in: Circle())
                }
                .buttonStyle(ScaleButtonStyle())
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            if isExpanded {
                // Gradient divider
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, Color.accentColor.opacity(0.2), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
                    .padding(.horizontal, 14)

                VStack(spacing: 16) {
                    // MARK: - Teleport Button
                    if let coord = mapVM.selectedCoordinate {
                        Button {
                            deviceManager.triggerSpoofAction {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                                    deviceManager.teleportTo(coord)
                                    teleportPulse = true
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    teleportPulse = false
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.blue.opacity(0.15))
                                        .frame(width: 36, height: 36)
                                        .scaleEffect(teleportPulse ? 1.4 : 1)
                                        .opacity(teleportPulse ? 0 : 1)

                                    Image(systemName: "location.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 36, height: 36)
                                        .background(
                                            LinearGradient(
                                                colors: [Color(red: 0.3, green: 0.55, blue: 1.0), Color(red: 0.2, green: 0.4, blue: 0.95)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            in: Circle()
                                        )
                                        .shadow(color: .blue.opacity(0.4), radius: 6, y: 2)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Teleport Here")
                                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text(String(format: "%.5f, %.5f", coord.latitude, coord.longitude))
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.blue.opacity(0.06))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .strokeBorder(Color.blue.opacity(0.15), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }

                    // MARK: - Speed Control
                    if mapVM.isRouteMode || !mapVM.gpxTrackPoints.isEmpty {
                        VStack(spacing: 10) {
                            HStack {
                                Image(systemName: "gauge.with.needle.fill")
                                    .foregroundStyle(.orange.gradient)
                                    .font(.system(size: 14))

                                Text("Speed")
                                    .font(.system(.subheadline, design: .rounded, weight: .medium))

                                Spacer()

                                // Animated speed display
                                HStack(alignment: .firstTextBaseline, spacing: 2) {
                                    Text("\(Int(mapVM.speedKmh))")
                                        .font(.system(.title3, design: .rounded, weight: .bold))
                                        .foregroundStyle(.orange)
                                        .contentTransition(.numericText(value: mapVM.speedKmh))
                                        .animation(.snappy, value: mapVM.speedKmh)

                                    Text("km/h")
                                        .font(.system(.caption, design: .rounded, weight: .medium))
                                        .foregroundStyle(.orange.opacity(0.7))
                                }
                            }

                            // Custom styled slider
                            Slider(value: $mapVM.speedKmh, in: 1...275, step: 1)
                                .tint(
                                    LinearGradient(
                                        colors: [.yellow, .orange, .red],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )

                            // Speed presets
                            HStack(spacing: 5) {
                                SpeedPresetChip(label: "🚶", subtitle: "5", speed: 5, current: $mapVM.speedKmh)
                                SpeedPresetChip(label: "🏃", subtitle: "12", speed: 12, current: $mapVM.speedKmh)
                                SpeedPresetChip(label: "🚴", subtitle: "25", speed: 25, current: $mapVM.speedKmh)
                                SpeedPresetChip(label: "🚗", subtitle: "60", speed: 60, current: $mapVM.speedKmh)
                                SpeedPresetChip(label: "✈️", subtitle: "120", speed: 120, current: $mapVM.speedKmh)
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // MARK: - Transport Mode
                    if mapVM.isRouteMode {
                        HStack(spacing: 10) {
                            Image(systemName: "road.lanes")
                                .foregroundStyle(.teal.gradient)
                                .font(.system(size: 14))

                            Text("Route")
                                .font(.system(.subheadline, design: .rounded, weight: .medium))

                            Spacer()

                            Picker("", selection: $mapVM.transportMode) {
                                ForEach(TransportMode.allCases, id: \.self) { mode in
                                    Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 150)
                            .onChange(of: mapVM.transportMode) { _, _ in
                                mapVM.calculateRoute()
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // MARK: - Route Info & Start
                    if !mapVM.routeCoordinates.isEmpty {
                        VStack(spacing: 12) {
                            // Route stats
                            HStack(spacing: 16) {
                                RouteStatPill(icon: "arrow.triangle.swap", value: mapVM.formattedDistance, color: .blue)
                                RouteStatPill(icon: "clock.fill", value: mapVM.formattedDuration, color: .purple)
                                RouteStatPill(icon: "mappin.and.ellipse", value: "\(mapVM.waypoints.count) pts", color: .orange)
                            }

                            // Progress bar (only when simulation is running)
                            if deviceManager.simulationMode == .routeSimulation || deviceManager.simulationMode == .gpxPlayback {
                                VStack(spacing: 4) {
                                    HStack {
                                        Text("Route Progress")
                                            .font(.system(size: 10, weight: .bold, design: .rounded))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(Int(deviceManager.simulationProgress * 100))%")
                                            .font(.system(size: 10, weight: .bold, design: .rounded))
                                            .foregroundStyle(Color.accentColor)
                                    }
                                    
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.primary.opacity(0.1))
                                            .frame(height: 6)
                                        
                                        GeometryReader { geo in
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [.blue, .cyan, .green],
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    )
                                                )
                                                .frame(width: geo.size.width * CGFloat(deviceManager.simulationProgress), height: 6)
                                        }
                                        .frame(height: 6)
                                    }
                                    .frame(height: 6)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                    .animation(.snappy, value: deviceManager.simulationProgress)
                                }
                                .padding(.top, 4)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            // Start button
                            Button {
                                deviceManager.triggerSpoofAction {
                                    deviceManager.simulateRoute(
                                        mapVM.routeCoordinates,
                                        speedKmh: mapVM.speedKmh,
                                        mode: mapVM.gpxTrackPoints.isEmpty ? .routeSimulation : .gpxPlayback
                                    )
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Start Simulation")
                                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    LinearGradient(
                                        colors: [Color(red: 0.2, green: 0.8, blue: 0.4), Color(red: 0.15, green: 0.65, blue: 0.35)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    in: RoundedRectangle(cornerRadius: 12)
                                )
                                .shadow(color: .green.opacity(0.3), radius: 8, y: 3)
                            }
                            .buttonStyle(GlowButtonStyle(color: .green))
                            .disabled(deviceManager.simulationMode == .routeSimulation || deviceManager.simulationMode == .gpxPlayback)
                            .opacity(deviceManager.simulationMode == .routeSimulation || deviceManager.simulationMode == .gpxPlayback ? 0.5 : 1)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // MARK: - Anti-Detection Toggle
                    Toggle(isOn: $deviceManager.antiDetectionEnabled) {
                        HStack(spacing: 6) {
                            Image(systemName: "shield.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(deviceManager.antiDetectionEnabled ? .green : .secondary)
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Anti-Detection Shield")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                                Text("Snapchat Safe Guard: location noise & timing")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                    .tint(.green)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)

                    // MARK: - Stop / Reset
                    HStack(spacing: 8) {
                        if deviceManager.simulationMode != .idle {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    deviceManager.stopSimulation()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "stop.fill")
                                        .font(.system(size: 11))
                                    Text("Stop")
                                        .font(.system(.caption, design: .rounded, weight: .bold))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(
                                    LinearGradient(
                                        colors: [.orange, Color(red: 0.9, green: 0.5, blue: 0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                                .shadow(color: .orange.opacity(0.3), radius: 6, y: 2)
                            }
                            .buttonStyle(GlowButtonStyle(color: .orange))
                            .transition(.scale.combined(with: .opacity))
                        }

                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                deviceManager.resetDeviceLocation()
                                mapVM.clearWaypoints()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                Text("Reset")
                                    .font(.system(.caption, design: .rounded, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 0.9, green: 0.25, blue: 0.3), Color(red: 0.75, green: 0.15, blue: 0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                            .shadow(color: .red.opacity(0.3), radius: 6, y: 2)
                        }
                        .buttonStyle(GlowButtonStyle(color: .red))
                    }
                }
                .padding(16)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: mapVM.isRouteMode)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: mapVM.routeCoordinates.count)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: deviceManager.simulationMode)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: mapVM.selectedCoordinate)
            }
        }
        .frame(width: 320)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(.ultraThinMaterial)

                // Subtle edge gradient
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.06), .clear, .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            }
        )
        .shadow(color: .black.opacity(0.2), radius: 24, y: 10)
    }
}

// MARK: - Simulation Badge

struct SimulationBadge: View {
    let mode: SimulationMode
    @State private var glow = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(modeColor)
                .frame(width: 5, height: 5)
                .shadow(color: modeColor.opacity(glow ? 0.8 : 0.3), radius: glow ? 6 : 2)

            Text(mode.rawValue)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(modeColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(modeColor.opacity(0.1), in: Capsule())
        .onAppear {
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
    }

    var modeColor: Color {
        switch mode {
        case .idle: return .secondary
        case .teleported: return .blue
        case .routeSimulation: return .green
        case .gpxPlayback: return .teal
        case .joystick: return .purple
        }
    }
}

// MARK: - Speed Preset Chip

struct SpeedPresetChip: View {
    let label: String
    let subtitle: String
    let speed: Double
    @Binding var current: Double

    var isActive: Bool { abs(current - speed) < 1 }
    @State private var isHovered = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                current = speed
            }
        } label: {
            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: 14))
                Text(subtitle)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(isActive ? .orange : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isActive
                            ? Color.orange.opacity(0.15)
                            : isHovered ? Color.primary.opacity(0.04) : Color.secondary.opacity(0.04)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isActive ? Color.orange.opacity(0.3) : .clear, lineWidth: 1)
                    )
            )
            .scaleEffect(isActive ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Route Stat Pill

struct RouteStatPill: View {
    let icon: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color)

            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.08), in: Capsule())
    }
}

#Preview {
    ControlPanelView()
        .environmentObject(DeviceSpoofManager.shared)
        .environmentObject(MapViewModel())
        .padding()
}
