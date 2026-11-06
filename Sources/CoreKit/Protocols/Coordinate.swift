import Foundation

/// Coordonnees geographiques — type domaine partage.
///
/// Utilise par `LocationSnapshot` et les features qui ont besoin
/// de coordonnees sans dependre de LocationKit/CoreLocation.
public struct Coordinate: Sendable, Equatable, Codable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Snapshot complet d'une position geographique.
///
/// Contient toutes les donnees utiles (vitesse, precision, cap, altitude)
/// sans dependre de CoreLocation. Les features consomment ce type
/// via `LocationServiceProtocol` au lieu de `LocationKit.LocationData`.
public struct LocationSnapshot: Sendable, Equatable {
    public let coordinate: Coordinate
    public let altitude: Double
    public let horizontalAccuracy: Double
    public let verticalAccuracy: Double
    public let speed: Double
    public let course: Double
    public let timestamp: Date

    public init(
        coordinate: Coordinate,
        altitude: Double = 0,
        horizontalAccuracy: Double = 0,
        verticalAccuracy: Double = 0,
        speed: Double = 0,
        course: Double = 0,
        timestamp: Date = Date()
    ) {
        self.coordinate = coordinate
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.speed = speed
        self.course = course
        self.timestamp = timestamp
    }

    public var latitude: Double { coordinate.latitude }
    public var longitude: Double { coordinate.longitude }
}
