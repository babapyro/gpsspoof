import SwiftUI

/// Floating capsule-shaped status bar with breathing animations and rich visual indicators.
struct StatusBarView: View {
    @EnvironmentObject var deviceManager: DeviceSpoofManager

    @State private var connectionPulse = false
    @State private var speedPulse = false

    var body: some View {
        HStack(spacing: 0) {
            // Connection segment
            HStack(spacing: 8) {
                // Animated connection dot
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.3))
                        .frame(width: 16, height: 16)
                        .scaleEffect(connectionPulse ? 1.4 : 0.8)
                        .opacity(connectionPulse ? 0 : 0.5)

                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                        .shadow(color: statusColor.opacity(0.7), radius: 4)
                }

                if let device = deviceManager.selectedDevice {
                    Text(device.name)
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .lineLimit(1)

                    // Connection type icon
                    Image(systemName: device.connectionType == .usb ? "cable.connector" : "wifi")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Text("No Device")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            // Mode segment (only when active)
            if deviceManager.simulationMode != .idle {
                // Separator
                RoundedRectangle(cornerRadius: 1)
                    .fill(.primary.opacity(0.1))
                    .frame(width: 1, height: 14)
                    .padding(.horizontal, 10)
                    .transition(.opacity)

                HStack(spacing: 6) {
                    // Mode icon
                    Image(systemName: modeIcon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(modeColor)
                        .symbolEffect(.bounce, value: deviceManager.simulationMode)

                    Text(deviceManager.simulationMode.rawValue)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(modeColor)
                        .contentTransition(.interpolate)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))

                // Speed badge
                if deviceManager.currentSpeed > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "gauge.with.needle")
                            .font(.system(size: 8, weight: .bold))

                        Text("\(Int(deviceManager.currentSpeed))")
                            .font(.system(.caption2, design: .rounded, weight: .bold))
                            .contentTransition(.numericText(value: deviceManager.currentSpeed))
                            .animation(.snappy, value: deviceManager.currentSpeed)

                        Text("km/h")
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(.orange.opacity(0.12))
                            .overlay(
                                Capsule()
                                    .strokeBorder(.orange.opacity(0.2), lineWidth: 0.5)
                            )
                    )
                    .padding(.leading, 4)
                    .scaleEffect(speedPulse ? 1.05 : 1)
                    .transition(.scale.combined(with: .opacity))
                    .onChange(of: deviceManager.currentSpeed) { _, _ in
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                            speedPulse = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            speedPulse = false
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            ZStack {
                Capsule()
                    .fill(.ultraThinMaterial)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.05), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Capsule()
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            }
        )
        .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: deviceManager.simulationMode)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: deviceManager.currentSpeed)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                connectionPulse = true
            }
        }
    }

    private var statusColor: Color {
        guard let device = deviceManager.selectedDevice else { return .red }
        return device.isConnected ? .green : .red
    }

    private var modeIcon: String {
        switch deviceManager.simulationMode {
        case .idle: return "pause.circle"
        case .teleported: return "location.fill"
        case .routeSimulation: return "road.lanes"
        case .gpxPlayback: return "point.topleft.down.to.point.bottomright.curvepath"
        case .joystick: return "dpad.fill"
        }
    }

    private var modeColor: Color {
        switch deviceManager.simulationMode {
        case .idle: return .secondary
        case .teleported: return .blue
        case .routeSimulation: return .green
        case .gpxPlayback: return .teal
        case .joystick: return .purple
        }
    }
}

#Preview {
    StatusBarView()
        .environmentObject(DeviceSpoofManager.shared)
        .padding()
}
