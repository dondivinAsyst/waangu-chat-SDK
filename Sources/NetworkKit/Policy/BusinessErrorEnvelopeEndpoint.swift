// MARK: - NetworkKit/Policy/BusinessErrorEnvelopeEndpoint.swift

import Foundation

/// Endpoint dont les réponses d'erreur **métier** portent un code à lire.
///
/// Par défaut, une réponse 4xx devient un `APIError` construit depuis le statut
/// HTTP et un message texte : le corps est perdu. Pour Chat Core Finance, c'est
/// rédhibitoire — un même 403 peut signifier pays non autorisé (`CF_003`),
/// capacité fermée (`CF_005`), gel conformité (`CF_010`), coupe-circuit
/// (`CF_069`) ou mode sans échec (`CF_072`), et le contrat impose de brancher
/// l'interface sur **le code**, jamais sur le texte.
///
/// Un endpoint qui adopte ce protocole reçoit donc le corps tel quel lorsque la
/// réponse 4xx est une enveloppe portant `error.code`. Le décodage de
/// l'enveloppe revient à la couche Data de la feature.
///
/// Le contrat envoie aussi des codes métier avec un **5xx** — `CF_052` (Biller
/// Hub non câblé), `CF_056` (marchand indisponible), `CF_068` (haut risque),
/// `CF_063` (traduction absente), tous en 503. Ce sont des réponses décidées
/// par le serveur, pas des pannes : les rejouer trois fois ne change rien, et
/// l'écran perdait le code et son message au profit d'un « 503 ».
///
/// Inchangé pour tous les autres endpoints. Même pour celui-ci :
/// - 401 garde le rafraîchissement de jeton ;
/// - 429 garde la limitation de débit ;
/// - un 5xx **sans** code métier (page HTML, corps vide, proxy) garde le
///   disjoncteur et la politique de retry ;
/// - un 4xx sans code métier garde l'erreur habituelle.
public protocol BusinessErrorEnvelopeEndpoint: Sendable {}

enum BusinessErrorEnvelope {

    /// `true` si le corps est une enveloppe `{ "error": { "code": "…" } }`.
    static func carriesBusinessCode(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any],
              let code = error["code"] as? String else { return false }
        return !code.isEmpty
    }

    /// Statuts dont le corps métier est remis à l'appelant — **s'il porte un
    /// code** : voir `delivers(statusCode:body:)`.
    static func passesThrough(statusCode: Int) -> Bool {
        (400...599).contains(statusCode) && statusCode != 401 && statusCode != 429
    }

    /// `true` si cette réponse est une décision métier à remettre telle quelle :
    /// statut admis **et** enveloppe portant `error.code`. Une panne sans code
    /// n'y entre jamais.
    static func delivers(statusCode: Int, body: Data) -> Bool {
        passesThrough(statusCode: statusCode) && carriesBusinessCode(body)
    }
}
