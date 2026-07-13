import Foundation
import CoreLocation
import MapKit

/// Handles route calculation via MKDirections and coordinate interpolation for smooth simulation.
final class RouteSimulator {

    /// Calculate a route between waypoints using Apple Maps directions
    static func calculateRoute(
        waypoints: [CLLocationCoordinate2D],
        transportType: MKDirectionsTransportType
    ) async throws -> [CLLocationCoordinate2D] {
        guard waypoints.count >= 2 else { return waypoints }

        var allCoordinates: [CLLocationCoordinate2D] = []

        for i in 0..<(waypoints.count - 1) {
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: waypoints[i]))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: waypoints[i + 1]))
            request.transportType = transportType
            request.requestsAlternateRoutes = false

            let directions = MKDirections(request: request)
            let response = try await directions.calculate()

            guard let route = response.routes.first else {
                // Fallback: straight line if no route found
                allCoordinates.append(waypoints[i])
                continue
            }

            let polyline = route.polyline
            let pointCount = polyline.pointCount
            let points = polyline.points()

            for j in 0..<pointCount {
                let mapPoint = points[j]
                let coord = mapPoint.coordinate
                // Avoid duplicating the junction point
                if j == 0 && !allCoordinates.isEmpty { continue }
                allCoordinates.append(coord)
            }
        }

        return allCoordinates
    }

    /// Interpolate coordinates along a polyline to ensure smooth movement at given intervals
    static func interpolate(
        coordinates: [CLLocationCoordinate2D],
        intervalMeters: Double = 5.0
    ) -> [CLLocationCoordinate2D] {
        guard coordinates.count >= 2 else { return coordinates }

        var result: [CLLocationCoordinate2D] = [coordinates[0]]

        for i in 0..<(coordinates.count - 1) {
            let start = coordinates[i]
            let end = coordinates[i + 1]
            let segmentDist = start.distance(to: end)

            if segmentDist <= intervalMeters {
                result.append(end)
                continue
            }

            let steps = Int(segmentDist / intervalMeters)
            for step in 1...steps {
                let fraction = Double(step) / Double(steps)
                let lat = start.latitude + (end.latitude - start.latitude) * fraction
                let lon = start.longitude + (end.longitude - start.longitude) * fraction
                result.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            }
        }

        return result
    }

    /// Calculate total distance of a coordinate array in meters
    static func totalDistance(_ coordinates: [CLLocationCoordinate2D]) -> CLLocationDistance {
        guard coordinates.count >= 2 else { return 0 }
        var total: CLLocationDistance = 0
        for i in 0..<(coordinates.count - 1) {
            total += coordinates[i].distance(to: coordinates[i + 1])
        }
        return total
    }

    /// Estimate duration for a route at given speed
    static func estimatedDuration(distance: CLLocationDistance, speedKmh: Double) -> TimeInterval {
        let speedMps = speedKmh / 3.6
        return distance / speedMps
    }
}
