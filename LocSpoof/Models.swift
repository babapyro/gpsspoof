import Foundation
import CoreLocation
import MapKit

// MARK: - Device Model

enum DeviceConnectionType: String, Codable {
    case usb = "USB"
    case wifi = "Wi-Fi"
}

enum DevicePlatform: String, Codable {
    case ios = "iOS"
    case android = "Android"
}

struct ConnectedDevice: Identifiable, Hashable {
    let id: String          // UDID / Serial
    let name: String
    let model: String
    let osVersion: String
    let connectionType: DeviceConnectionType
    let platform: DevicePlatform
    var isConnected: Bool = true

    var displayName: String {
        "\(name) (\(model))"
    }

    var isiOS17OrLater: Bool {
        guard platform == .ios else { return false }
        guard let major = osVersion.split(separator: ".").first,
              let version = Int(major) else { return false }
        return version >= 17
    }
}

// MARK: - Simulation State

enum SimulationMode: String {
    case idle = "Idle"
    case teleported = "Teleported"
    case routeSimulation = "Route Simulation"
    case gpxPlayback = "GPX Playback"
    case joystick = "Joystick"
}

enum TransportMode: String, CaseIterable {
    case walking = "Walking"
    case driving = "Driving"

    var mkTransportType: MKDirectionsTransportType {
        switch self {
        case .walking: return .walking
        case .driving: return .automobile
        }
    }

    var icon: String {
        switch self {
        case .walking: return "figure.walk"
        case .driving: return "car.fill"
        }
    }
}

// MARK: - Route Waypoint

struct RouteWaypoint: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let index: Int
}

// MARK: - GPX Track Point

struct GPXTrackPoint {
    let coordinate: CLLocationCoordinate2D
    let elevation: Double?
    let timestamp: Date?
}

// MARK: - Coordinate Extension

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

extension CLLocationCoordinate2D: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(latitude)
        hasher.combine(longitude)
    }
}

extension CLLocationCoordinate2D {
    /// Returns distance in meters to another coordinate
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        let from = CLLocation(latitude: latitude, longitude: longitude)
        let to = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return from.distance(from: to)
    }

    /// Returns bearing in radians to another coordinate
    func bearing(to other: CLLocationCoordinate2D) -> Double {
        let lat1 = latitude.degreesToRadians
        let lat2 = other.latitude.degreesToRadians
        let dLon = (other.longitude - longitude).degreesToRadians

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return atan2(y, x)
    }

    /// Returns a new coordinate offset by distance (meters) at bearing (radians)
    func offset(distance: Double, bearing: Double) -> CLLocationCoordinate2D {
        let earthRadius = 6371000.0
        let lat1 = latitude.degreesToRadians
        let lon1 = longitude.degreesToRadians

        let lat2 = asin(sin(lat1) * cos(distance / earthRadius) +
                        cos(lat1) * sin(distance / earthRadius) * cos(bearing))
        let lon2 = lon1 + atan2(sin(bearing) * sin(distance / earthRadius) * cos(lat1),
                                cos(distance / earthRadius) - sin(lat1) * sin(lat2))

        return CLLocationCoordinate2D(latitude: lat2.radiansToDegrees,
                                      longitude: lon2.radiansToDegrees)
    }
}

extension Double {
    var degreesToRadians: Double { self * .pi / 180 }
    var radiansToDegrees: Double { self * 180 / .pi }
}
