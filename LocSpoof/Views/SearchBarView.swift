import SwiftUI
import MapKit

/// Floating search bar with animated dropdown, hover highlights, and smooth transitions.
struct SearchBarView: View {
    @EnvironmentObject var mapVM: MapViewModel

    @FocusState private var isFocused: Bool
    @State private var isHovered = false
    @State private var hoveredResultId: MKMapItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search input
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isFocused ? Color.accentColor : .secondary)
                    .animation(.easeOut(duration: 0.2), value: isFocused)

                TextField("Search location…", text: $mapVM.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .rounded))
                    .focused($isFocused)
                    .onSubmit {
                        mapVM.searchLocation()
                    }

                if !mapVM.searchText.isEmpty {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            mapVM.searchText = ""
                            mapVM.searchResults = []
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .transition(.scale.combined(with: .opacity))
                }

                if mapVM.isSearching {
                    ProgressView()
                        .scaleEffect(0.65)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .animation(.easeOut(duration: 0.2), value: mapVM.searchText.isEmpty)

            // Results dropdown
            if !mapVM.searchResults.isEmpty {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .primary.opacity(0.06), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(mapVM.searchResults.enumerated()), id: \.element) { index, item in
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    mapVM.selectSearchResult(item)
                                    isFocused = false
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.red.opacity(hoveredResultId == item ? 0.15 : 0.08))
                                            .frame(width: 32, height: 32)

                                        Image(systemName: "mappin.circle.fill")
                                            .font(.system(size: 15))
                                            .foregroundStyle(.red)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name ?? "Unknown")
                                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)

                                        if let subtitle = item.placemark.formattedAddress {
                                            Text(subtitle)
                                                .font(.system(.caption2, design: .rounded))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.tertiary)
                                        .opacity(hoveredResultId == item ? 1 : 0)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(hoveredResultId == item ? Color.primary.opacity(0.04) : .clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .onHover { h in
                                withAnimation(.easeOut(duration: 0.12)) {
                                    hoveredResultId = h ? item : nil
                                }
                            }

                            if index < mapVM.searchResults.count - 1 {
                                Divider()
                                    .padding(.leading, 52)
                                    .opacity(0.5)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 220)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: 380)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)

                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.05), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isFocused ? Color.accentColor.opacity(0.3) : .white.opacity(0.08),
                        lineWidth: isFocused ? 1.5 : 1
                    )
                    .animation(.easeOut(duration: 0.2), value: isFocused)
            }
        )
        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: mapVM.searchResults.count)
    }
}

// MARK: - MKPlacemark address helper

extension MKPlacemark {
    var formattedAddress: String? {
        let components = [
            subThoroughfare,
            thoroughfare,
            locality,
            administrativeArea,
            country
        ].compactMap { $0 }
        return components.isEmpty ? nil : components.joined(separator: ", ")
    }
}

#Preview {
    SearchBarView()
        .environmentObject(MapViewModel())
        .padding()
        .frame(width: 420)
}
