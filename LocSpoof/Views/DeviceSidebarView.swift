import SwiftUI

struct DeviceSidebarView: View {
    @EnvironmentObject var deviceManager: DeviceSpoofManager
    @EnvironmentObject var mapVM: MapViewModel
    @ObservedObject private var licenseManager = LicenseManager.shared

    @State private var headerGlow = false
    @State private var hoveredDeviceId: String?

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(headerGlow ? 0.15 : 0.08))
                        .frame(width: 36, height: 36)
                        .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: headerGlow)

                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .symbolEffect(.variableColor.iterative, options: .repeating, isActive: deviceManager.isScanning)
                }

                Text("Devices")
                    .font(.system(.title2, design: .rounded, weight: .bold))

                Spacer()

                Button {
                    deviceManager.scanForDevices()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(.quaternary.opacity(0.5), in: Circle())
                        .rotationEffect(.degrees(deviceManager.isScanning ? 360 : 0))
                        .animation(
                            deviceManager.isScanning
                                ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                                : .default,
                            value: deviceManager.isScanning
                        )
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(deviceManager.isScanning)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 14)
            .onAppear { headerGlow = true }

            // Gradient divider
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.accentColor.opacity(0.3), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .padding(.horizontal, 16)

            // MARK: - Device List
            if deviceManager.devices.isEmpty {
                emptyDevicesView
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(deviceManager.devices, id: \.id) { device in
                            DeviceRow(
                                device: device,
                                isSelected: deviceManager.selectedDevice?.id == device.id,
                                isHovered: hoveredDeviceId == device.id
                            )
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    deviceManager.selectedDevice = device
                                }
                            }
                            .onHover { isHovering in
                                withAnimation(.easeOut(duration: 0.15)) {
                                    hoveredDeviceId = isHovering ? device.id : nil
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }

            // Gradient divider
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .primary.opacity(0.08), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .padding(.horizontal, 16)

            // MARK: - Coordinate Display
            if mapVM.selectedCoordinate != nil || deviceManager.currentSpoofedLocation != nil {
                VStack(spacing: 6) {
                    if let coord = mapVM.selectedCoordinate {
                        CoordinateRow(label: "Selected", lat: coord.latitude, lon: coord.longitude, color: .red)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    if let spoofed = deviceManager.currentSpoofedLocation {
                        CoordinateRow(label: "Spoofed", lat: spoofed.latitude, lon: spoofed.longitude, color: .cyan)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: mapVM.selectedCoordinate)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: deviceManager.currentSpoofedLocation)
            }

            // MARK: - Quick Actions
            VStack(spacing: 8) {
                SidebarActionButton(
                    label: "Import GPX File",
                    icon: "doc.badge.plus",
                    tintColor: .teal,
                    isActive: false,
                    isProFeature: true
                ) {
                    if licenseManager.isPremiumUser {
                        mapVM.importGPXFile()
                    } else {
                        licenseManager.showProPaywall = true
                    }
                }

                SidebarActionButton(
                    label: mapVM.isRouteMode ? "Exit Route Mode" : "Route Mode",
                    icon: mapVM.isRouteMode ? "xmark.circle.fill" : "point.topleft.down.to.point.bottomright.curvepath.fill",
                    tintColor: .orange,
                    isActive: mapVM.isRouteMode,
                    isProFeature: true
                ) {
                    if licenseManager.isPremiumUser {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                            mapVM.isRouteMode.toggle()
                            if !mapVM.isRouteMode { mapVM.clearWaypoints() }
                        }
                    } else {
                        licenseManager.showProPaywall = true
                    }
                }

                SidebarActionButton(
                    label: mapVM.showJoystick ? "Hide Joystick" : "Joystick Mode",
                    icon: "dpad.fill",
                    tintColor: .purple,
                    isActive: mapVM.showJoystick,
                    isProFeature: true
                ) {
                    if licenseManager.isPremiumUser {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                            mapVM.showJoystick.toggle()
                        }
                    } else {
                        licenseManager.showProPaywall = true
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)

            // MARK: - License Status / Buy
            VStack(spacing: 8) {
                Divider()
                    .padding(.horizontal, 16)
                    .opacity(0.6)
                
                if LicenseManager.shared.isTrialMode {
                    Link(destination: URL(string: "https://pyrollc.com.tr/locspoof")!) {
                        HStack(spacing: 8) {
                            Image(systemName: "cart.fill")
                                .font(.system(size: 13, weight: .bold))
                            Text("Buy License Key")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [.orange, Color(red: 0.9, green: 0.4, blue: 0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .shadow(color: .orange.opacity(0.2), radius: 6, y: 2)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.green)
                        Text("LocSpoof Premium Active")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .padding(.bottom, 12)
                }
            }
        }
        .background(
            ZStack {
                // Base material
                Rectangle()
                    .fill(.ultraThinMaterial)

                // Subtle gradient tint
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.03), .clear, Color.purple.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
    }

    // MARK: - Empty State

    private var emptyDevicesView: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.06))
                    .frame(width: 80, height: 80)

                Image(systemName: deviceManager.isScanning ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.secondary.opacity(0.6))
                    .symbolEffect(.pulse, isActive: deviceManager.isScanning)
            }

            VStack(spacing: 6) {
                Text(deviceManager.isScanning ? "Scanning…" : "No Devices")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("Connect an iOS or Android device\nvia USB or Wi-Fi")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

// MARK: - Device Row

struct DeviceRow: View {
    let device: ConnectedDevice
    let isSelected: Bool
    let isHovered: Bool

    @State private var dotGlow = false

    var body: some View {
        HStack(spacing: 12) {
            // Device icon with glow
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.12)
                            : isHovered
                                ? Color.secondary.opacity(0.08)
                                : Color.secondary.opacity(0.04)
                    )
                    .frame(width: 42, height: 42)

                Image(systemName: device.connectionType == .usb ? "cable.connector" : "wifi")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .symbolEffect(.bounce, value: isSelected)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(device.model)
                    Text("·")
                    Text("\(device.platform.rawValue) \(device.osVersion)")
                }
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Connection dot with glow
            ZStack {
                Circle()
                    .fill(device.isConnected ? .green.opacity(0.2) : .red.opacity(0.2))
                    .frame(width: 18, height: 18)
                    .scaleEffect(dotGlow ? 1.2 : 0.8)
                    .opacity(dotGlow ? 0 : 0.4)

                Circle()
                    .fill(device.isConnected ? .green : .red)
                    .frame(width: 8, height: 8)
                    .shadow(color: (device.isConnected ? Color.green : .red).opacity(0.6), radius: 4)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    dotGlow = true
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(0.08)
                        : isHovered
                            ? Color.primary.opacity(0.03)
                            : .clear
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isSelected
                                ? Color.accentColor.opacity(0.25)
                                : isHovered
                                    ? Color.primary.opacity(0.06)
                                    : .clear,
                            lineWidth: 1
                        )
                )
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Sidebar Action Button

struct SidebarActionButton: View {
    let label: String
    let icon: String
    let tintColor: Color
    let isActive: Bool
    var isProFeature: Bool = false
    let action: () -> Void

    @State private var isHovered = false
    @ObservedObject private var licenseManager = LicenseManager.shared

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isActive ? tintColor : .secondary)
                    .frame(width: 20)

                Text(label)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(isActive ? tintColor : .primary)

                Spacer()

                if isProFeature && !licenseManager.isPremiumUser {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.yellow)
                } else if isActive {
                    Circle()
                        .fill(tintColor)
                        .frame(width: 6, height: 6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        isActive
                            ? tintColor.opacity(0.1)
                            : isHovered ? Color.primary.opacity(0.04) : .clear
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                isActive ? tintColor.opacity(0.2) : .clear,
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Coordinate Row

struct CoordinateRow: View {
    let label: String
    let lat: Double
    let lon: Double
    let color: Color

    @State private var dotGlow = false

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 14, height: 14)
                    .scaleEffect(dotGlow ? 1.3 : 0.8)
                    .opacity(dotGlow ? 0 : 0.4)

                Circle()
                    .fill(color.gradient)
                    .frame(width: 7, height: 7)
                    .shadow(color: color.opacity(0.5), radius: 3)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    dotGlow = true
                }
            }

            Text(label)
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Text(String(format: "%.5f, %.5f", lat, lon))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }
}

#Preview {
    DeviceSidebarView()
        .environmentObject(DeviceSpoofManager.shared)
        .environmentObject(MapViewModel())
        .frame(width: 290, height: 700)
}
