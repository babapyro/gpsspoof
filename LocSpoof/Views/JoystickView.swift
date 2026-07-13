import SwiftUI

/// Premium virtual joystick with fluid drag, glow effects, and directional feedback.
struct JoystickView: View {
    @EnvironmentObject var deviceManager: DeviceSpoofManager
    @EnvironmentObject var mapVM: MapViewModel

    @State private var knobOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var continuousTimer: Timer?
    @State private var currentBearing: Double = 0
    @State private var currentMagnitude: Double = 0
    @State private var ringRotation: Double = 0
    @State private var outerGlow = false

    private let outerRadius: CGFloat = 72
    private let knobRadius: CGFloat = 22
    private let stepDistanceMeters: Double = 2.0

    var body: some View {
        VStack(spacing: 14) {
            // Header with live direction
            HStack(spacing: 8) {
                Image(systemName: "dpad.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.purple.gradient)

                Text("Joystick")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))

                if isDragging {
                    Text("·")
                        .foregroundStyle(.tertiary)

                    Text(directionLabel)
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(.purple)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.15), value: directionLabel)

                    Spacer()

                    // Magnitude indicator
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(
                                    Double(i) / 5.0 < currentMagnitude
                                        ? Color.purple
                                        : Color.secondary.opacity(0.15)
                                )
                                .frame(width: 4, height: CGFloat(6 + i * 2))
                        }
                    }
                    .animation(.easeOut(duration: 0.1), value: currentMagnitude)
                }
            }

            // MARK: - Joystick Pad
            ZStack {
                // Animated outer ring
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            colors: [
                                .purple.opacity(0.4),
                                .blue.opacity(0.2),
                                .cyan.opacity(0.3),
                                .purple.opacity(0.4)
                            ],
                            center: .center
                        ),
                        lineWidth: 2
                    )
                    .frame(width: outerRadius * 2 + 8, height: outerRadius * 2 + 8)
                    .rotationEffect(.degrees(ringRotation))
                    .opacity(isDragging ? 1 : 0.4)

                // Outer disc
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.primary.opacity(0.04),
                                Color.primary.opacity(0.02),
                                Color.primary.opacity(0.06)
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: outerRadius
                        )
                    )
                    .frame(width: outerRadius * 2, height: outerRadius * 2)
                    .overlay(
                        Circle()
                            .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
                    )

                // Direction zone highlight
                if isDragging {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.purple.opacity(0.12), .clear],
                                center: UnitPoint(
                                    x: 0.5 + knobOffset.width / (outerRadius * 2),
                                    y: 0.5 + knobOffset.height / (outerRadius * 2)
                                ),
                                startRadius: 0,
                                endRadius: outerRadius * 0.8
                            )
                        )
                        .frame(width: outerRadius * 2, height: outerRadius * 2)
                        .transition(.opacity)
                }

                // Cross-hair
                crossHairGuides

                // Cardinal labels
                ForEach(cardinalDirections, id: \.label) { dir in
                    Text(dir.label)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary.opacity(isDragging ? 0.4 : 0.25))
                        .offset(dir.offset)
                }

                // Direction trail (line from center to knob)
                if isDragging {
                    Path { path in
                        path.move(to: CGPoint(x: outerRadius, y: outerRadius))
                        path.addLine(to: CGPoint(
                            x: outerRadius + knobOffset.width,
                            y: outerRadius + knobOffset.height
                        ))
                    }
                    .stroke(
                        LinearGradient(
                            colors: [.purple.opacity(0.05), .purple.opacity(0.3)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .frame(width: outerRadius * 2, height: outerRadius * 2)
                    .transition(.opacity)
                }

                // Inner knob
                ZStack {
                    // Knob glow
                    Circle()
                        .fill(.purple.opacity(isDragging ? 0.3 : 0))
                        .frame(width: knobRadius * 3, height: knobRadius * 3)
                        .blur(radius: 8)

                    // Knob body
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 0.65, green: 0.4, blue: 1.0),
                                    Color(red: 0.5, green: 0.25, blue: 0.9),
                                    Color(red: 0.35, green: 0.15, blue: 0.75)
                                ],
                                center: .init(x: 0.35, y: 0.3),
                                startRadius: 0,
                                endRadius: knobRadius
                            )
                        )
                        .frame(width: knobRadius * 2, height: knobRadius * 2)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [.white.opacity(0.4), .white.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(color: .purple.opacity(isDragging ? 0.6 : 0.25), radius: isDragging ? 14 : 6, y: 2)
                        .scaleEffect(isDragging ? 1.12 : 1.0)

                    // Inner dot
                    Circle()
                        .fill(.white.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .offset(x: -3, y: -3)
                }
                .offset(knobOffset)
                .gesture(joystickDragGesture)
                .animation(.spring(response: 0.2, dampingFraction: 0.55), value: isDragging)
            }

            // D-Pad buttons
            HStack(spacing: 6) {
                DPadButton(icon: "arrow.up", direction: "N") { moveTo(bearing: 0) }
                DPadButton(icon: "arrow.left", direction: "W") { moveTo(bearing: .pi * 1.5) }
                DPadButton(icon: "arrow.down", direction: "S") { moveTo(bearing: .pi) }
                DPadButton(icon: "arrow.right", direction: "E") { moveTo(bearing: .pi * 0.5) }
            }
        }
        .padding(20)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(.ultraThinMaterial)

                RoundedRectangle(cornerRadius: 22)
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.04), .clear, Color.blue.opacity(0.02)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            }
        )
        .shadow(color: .black.opacity(0.2), radius: 24, y: 10)
        .onAppear {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
        }
    }

    // MARK: - Drag Gesture

    private var joystickDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let translation = value.translation
                let distance = sqrt(translation.width * translation.width + translation.height * translation.height)
                let maxDist = outerRadius - knobRadius
                let clampedDist = min(distance, maxDist)
                let angle = atan2(translation.width, -translation.height)

                if distance > 0 {
                    let scale = clampedDist / distance
                    knobOffset = CGSize(
                        width: translation.width * scale,
                        height: translation.height * scale
                    )
                }

                currentBearing = angle
                currentMagnitude = clampedDist / maxDist

                if !isDragging {
                    withAnimation(.easeOut(duration: 0.2)) { isDragging = true }
                    deviceManager.simulationMode = .joystick
                    startContinuousMovement()
                }
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
                    knobOffset = .zero
                }
                withAnimation(.easeOut(duration: 0.2)) {
                    isDragging = false
                    currentMagnitude = 0
                }
                stopContinuousMovement()
            }
    }

    // MARK: - Movement Logic

    private func startContinuousMovement() {
        continuousTimer?.invalidate()
        deviceManager.triggerSpoofAction {
            continuousTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
                let dist = stepDistanceMeters * currentMagnitude * 2
                deviceManager.moveInDirection(bearing: currentBearing, distanceMeters: dist)
            }
        }
    }

    private func stopContinuousMovement() {
        continuousTimer?.invalidate()
        continuousTimer = nil
    }

    private func moveTo(bearing: Double) {
        deviceManager.triggerSpoofAction {
            deviceManager.moveInDirection(bearing: bearing, distanceMeters: stepDistanceMeters)
        }
    }

    // MARK: - Direction

    private var directionLabel: String {
        let deg = currentBearing * 180 / .pi
        let n = (deg + 360).truncatingRemainder(dividingBy: 360)
        switch n {
        case 337.5...360, 0..<22.5: return "N"
        case 22.5..<67.5: return "NE"
        case 67.5..<112.5: return "E"
        case 112.5..<157.5: return "SE"
        case 157.5..<202.5: return "S"
        case 202.5..<247.5: return "SW"
        case 247.5..<292.5: return "W"
        case 292.5..<337.5: return "NW"
        default: return ""
        }
    }

    // MARK: - Cardinal Data

    private struct CardinalDirection {
        let label: String
        let offset: CGSize
    }

    private var cardinalDirections: [CardinalDirection] {
        let r = outerRadius - 12
        return [
            .init(label: "N", offset: CGSize(width: 0, height: -r)),
            .init(label: "S", offset: CGSize(width: 0, height: r)),
            .init(label: "E", offset: CGSize(width: r, height: 0)),
            .init(label: "W", offset: CGSize(width: -r, height: 0)),
        ]
    }

    @ViewBuilder
    private var crossHairGuides: some View {
        Rectangle()
            .fill(.primary.opacity(isDragging ? 0.06 : 0.04))
            .frame(width: outerRadius * 1.4, height: 1)
        Rectangle()
            .fill(.primary.opacity(isDragging ? 0.06 : 0.04))
            .frame(width: 1, height: outerRadius * 1.4)
    }
}

// MARK: - D-Pad Button

struct DPadButton: View {
    let icon: String
    let direction: String
    let action: () -> Void

    @State private var isPressed = false
    @State private var isHovered = false

    var body: some View {
        Button {
            action()
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isPressed = false
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(direction)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 38, height: 38)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(
                        isPressed
                            ? Color.purple.opacity(0.15)
                            : isHovered ? Color.primary.opacity(0.06) : Color.primary.opacity(0.03)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(
                                isPressed ? Color.purple.opacity(0.3) : .clear,
                                lineWidth: 1
                            )
                    )
            )
            .scaleEffect(isPressed ? 0.9 : 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

#Preview {
    JoystickView()
        .environmentObject(DeviceSpoofManager.shared)
        .environmentObject(MapViewModel())
        .padding()
        .frame(width: 300, height: 380)
}
