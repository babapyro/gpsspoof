import SwiftUI
import MapKit
import CoreLocation
import Combine

/// Drives all map interactions: camera, annotations, route calculation, GPX import, and coordinate management.
@MainActor
final class MapViewModel: ObservableObject {

    // MARK: - Map State
    @Published var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 41.0082, longitude: 28.9784),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    ))

    @Published var selectedCoordinate: CLLocationCoordinate2D?
    @Published var waypoints: [RouteWaypoint] = []
    @Published var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published var routePolyline: MKPolyline?
    @Published var isCalculatingRoute: Bool = false

    // MARK: - Settings
    @Published var speedKmh: Double = 50.0
    @Published var transportMode: TransportMode = .driving
    @Published var isRouteMode: Bool = false
    @Published var showJoystick: Bool = false

    // MARK: - GPX
    @Published var gpxTrackPoints: [GPXTrackPoint] = []
    @Published var gpxPolyline: MKPolyline?

    // MARK: - Search
    @Published var searchText: String = ""
    @Published var searchResults: [MKMapItem] = []
    @Published var isSearching: Bool = false

    private let gpxParser = GPXParser()

    // MARK: - Map Tap Handling

    func handleMapTap(at coordinate: CLLocationCoordinate2D) {
        if isRouteMode {
            addWaypoint(at: coordinate)
        } else {
            selectedCoordinate = coordinate
            waypoints = []
            routeCoordinates = []
            routePolyline = nil
        }
    }

    // MARK: - Waypoint Management

    func addWaypoint(at coordinate: CLLocationCoordinate2D) {
        let wp = RouteWaypoint(coordinate: coordinate, index: waypoints.count)
        waypoints.append(wp)

        if waypoints.count >= 2 {
            calculateRoute()
        }
    }

    func clearWaypoints() {
        waypoints = []
        routeCoordinates = []
        routePolyline = nil
        selectedCoordinate = nil
    }

    // MARK: - Route Calculation

    func calculateRoute() {
        guard waypoints.count >= 2 else { return }
        isCalculatingRoute = true

        let coords = waypoints.map { $0.coordinate }
        let transport = transportMode.mkTransportType

        Task {
            do {
                let routeCoords = try await RouteSimulator.calculateRoute(
                    waypoints: coords,
                    transportType: transport
                )

                let interpolated = RouteSimulator.interpolate(coordinates: routeCoords, intervalMeters: 10)
                self.routeCoordinates = interpolated

                // Build polyline for display
                var polylineCoords = interpolated
                self.routePolyline = MKPolyline(coordinates: &polylineCoords, count: polylineCoords.count)
            } catch {
                print("Route calculation failed: \(error)")
                // Fallback: straight-line route
                self.routeCoordinates = coords
            }
            self.isCalculatingRoute = false
        }
    }

    // MARK: - GPX Import

    func importGPXFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.xml, .init(filenameExtension: "gpx")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a GPX file to import"

        panel.begin { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }

            Task { @MainActor in
                let points = self.gpxParser.parse(fileURL: url)
                guard !points.isEmpty else {
                    return
                }

                self.gpxTrackPoints = points
                let coords = points.map { $0.coordinate }

                // Create polyline for display
                var polylineCoords = coords
                self.gpxPolyline = MKPolyline(coordinates: &polylineCoords, count: polylineCoords.count)

                // Center map on GPX track
                if let first = coords.first {
                    self.cameraPosition = .region(MKCoordinateRegion(
                        center: first,
                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                    ))
                }

                // Store for simulation
                self.routeCoordinates = coords
                self.selectedCoordinate = coords.first
            }
        }
    }

    // MARK: - Search

    func searchLocation() {
        guard !searchText.isEmpty else {
            searchResults = []
            return
        }

        isSearching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText

        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, error in
            Task { @MainActor in
                guard let self = self else { return }
                self.isSearching = false
                if let items = response?.mapItems {
                    self.searchResults = items
                }
            }
        }
    }

    func selectSearchResult(_ item: MKMapItem) {
        let coord = item.placemark.coordinate
        selectedCoordinate = coord
        cameraPosition = .region(MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
        searchResults = []
        searchText = item.name ?? ""
    }

    // MARK: - Computed Properties

    var routeDistance: CLLocationDistance {
        RouteSimulator.totalDistance(routeCoordinates)
    }

    var estimatedDuration: TimeInterval {
        RouteSimulator.estimatedDuration(distance: routeDistance, speedKmh: speedKmh)
    }

    var formattedDistance: String {
        if routeDistance >= 1000 {
            return String(format: "%.1f km", routeDistance / 1000)
        }
        return String(format: "%.0f m", routeDistance)
    }

    var formattedDuration: String {
        let minutes = Int(estimatedDuration) / 60
        let seconds = Int(estimatedDuration) % 60
        if minutes > 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m \(seconds)s"
    }
}
