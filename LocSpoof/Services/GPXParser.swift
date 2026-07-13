import Foundation
import CoreLocation

/// Parses GPX (XML) files to extract track points for route playback.
final class GPXParser: NSObject, XMLParserDelegate {

    private var trackPoints: [GPXTrackPoint] = []
    private var currentElement: String = ""
    private var currentLat: Double?
    private var currentLon: Double?
    private var currentElevation: String = ""
    private var currentTime: String = ""

    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Parse a GPX file at the given URL and return an array of track points
    func parse(fileURL: URL) -> [GPXTrackPoint] {
        trackPoints = []
        guard let parser = XMLParser(contentsOf: fileURL) else { return [] }
        parser.delegate = self
        parser.parse()
        return trackPoints
    }

    /// Parse GPX data from a string
    func parse(xmlString: String) -> [GPXTrackPoint] {
        trackPoints = []
        guard let data = xmlString.data(using: .utf8) else { return [] }
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return trackPoints
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName

        if elementName == "trkpt" || elementName == "wpt" || elementName == "rtept" {
            currentLat = Double(attributeDict["lat"] ?? "")
            currentLon = Double(attributeDict["lon"] ?? "")
            currentElevation = ""
            currentTime = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentElement == "ele" {
            currentElevation += trimmed
        } else if currentElement == "time" {
            currentTime += trimmed
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "trkpt" || elementName == "wpt" || elementName == "rtept" {
            if let lat = currentLat, let lon = currentLon {
                let elevation = Double(currentElevation)
                let timestamp = Self.dateFormatter.date(from: currentTime)

                trackPoints.append(GPXTrackPoint(
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    elevation: elevation,
                    timestamp: timestamp
                ))
            }
        }
        currentElement = ""
    }
}
