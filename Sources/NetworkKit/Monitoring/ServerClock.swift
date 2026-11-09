// MARK: - NetworkKit/Monitoring/ServerClock.swift

import Foundation

/// L'heure du serveur, déduite de l'en-tête `Date` de ses réponses.
///
/// Un devis expire à l'heure du **serveur**. Comparer son `expiresAt` à l'horloge
/// du téléphone laisse un bouton de confirmation actif trop longtemps (téléphone
/// en retard) ou le grise trop tôt (téléphone en avance). Le serveur reste
/// l'autorité : il refuse de toute façon un devis périmé à l'exécution. Ce
/// décalage n'améliore que ce que l'écran affiche.
///
/// Précision : l'en-tête `Date` est à la seconde et ne tient pas compte du temps
/// de transit. Ce n'est pas une horloge de confiance, seulement un meilleur
/// repère que celle du téléphone. Sans réponse reçue, le décalage vaut zéro et
/// `now` est l'heure de l'appareil.
public final class ServerClock: @unchecked Sendable {

    public static let shared = ServerClock()

    private let lock = NSLock()
    private var offset: TimeInterval = 0

    /// Interne : les tests créent leur propre horloge plutôt que de modifier `shared`.
    init() {}

    /// L'heure du serveur, d'après la dernière réponse observée.
    public var now: Date { adjusted(Date()) }

    /// Ramène un instant de l'horloge de l'appareil à l'heure du serveur.
    public func adjusted(_ deviceDate: Date) -> Date {
        lock.lock(); defer { lock.unlock() }
        return deviceDate.addingTimeInterval(offset)
    }

    /// Retient l'écart entre l'en-tête `Date` d'une réponse et l'heure de réception.
    func observe(response: HTTPURLResponse, receivedAt: Date = Date()) {
        guard let header = response.value(forHTTPHeaderField: "Date"),
              let serverDate = Self.parse(header) else { return }
        lock.lock(); defer { lock.unlock() }
        offset = serverDate.timeIntervalSince(receivedAt)
    }

    /// Format HTTP (RFC 9110), ex. `Tue, 10 Nov 2026 09:30:00 GMT`.
    static func parse(_ header: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: header)
    }
}
