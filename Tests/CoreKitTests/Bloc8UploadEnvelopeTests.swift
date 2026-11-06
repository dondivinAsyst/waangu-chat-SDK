import Testing
import Foundation
@testable import WaanguCoreKit

/// Médias, enveloppe d'API et télémétrie — Bloc 8, §21, §24, §25, §26.
@Suite("Bloc 8 — médias, enveloppe et télémétrie")
struct Bloc8UploadEnvelopeTests {

    // MARK: - Reprise d'envoi (§21)

    private func checkpoint(hash: String = "h-1", uploaded: Int64 = 0,
                            total: Int64 = 10_000, chunk: Int64 = 4_000,
                            created: Date = Date()) -> UploadCheckpoint {
        UploadCheckpoint(uploadID: "u-1", fileHash: hash, uploadedBytes: uploaded,
                         totalBytes: total, chunkSize: chunk, createdAt: created)
    }

    @Test("Le prochain segment part de l'octet déjà envoyé")
    func nextRangeResumes() {
        #expect(checkpoint(uploaded: 4_000).nextRange == 4_000..<8_000)
    }

    @Test("Le dernier segment s'arrête à la taille du fichier")
    func lastChunkIsClamped() {
        // Sans borne, on demanderait des octets au-delà de la fin.
        #expect(checkpoint(uploaded: 8_000).nextRange == 8_000..<10_000)
    }

    @Test("Un envoi terminé n'a plus de segment")
    func completeHasNoRange() {
        let done = checkpoint(uploaded: 10_000)
        #expect(done.isComplete)
        #expect(done.nextRange == nil)
    }

    /// Le point le plus important du §21.
    @Test("Un point de reprise ne vaut plus si le fichier a changé")
    func checkpointRejectsChangedFile() {
        // Reprendre ici recollerait la fin d'un fichier à la tête d'un autre.
        #expect(!checkpoint(hash: "h-1").isValid(for: "h-2"))
        #expect(checkpoint(hash: "h-1").isValid(for: "h-1"))
    }

    @Test("Un point de reprise trop ancien est abandonné")
    func staleCheckpointExpires() {
        let old = checkpoint(created: Date(timeIntervalSinceNow: -200_000))
        #expect(!old.isValid(for: "h-1"))
    }

    // MARK: - Contraintes et type réel (§21)

    @Test("Un fichier trop gros est refusé")
    func oversizeRejected() {
        #expect(UploadConstraints.image.rejection(
            forSize: 50 * 1_048_576, mimeType: "image/png") == .tooLarge)
    }

    @Test("Un fichier vide est refusé")
    func emptyRejected() {
        #expect(UploadConstraints.image.rejection(
            forSize: 0, mimeType: "image/png") == .empty)
    }

    @Test("Un type non autorisé est refusé")
    func disallowedTypeRejected() {
        #expect(UploadConstraints.image.rejection(
            forSize: 1_000, mimeType: "application/zip") == .disallowedType)
    }

    @Test("Un PNG authentique passe")
    func genuinePNGPasses() {
        let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0, 0, 0, 0, 0]
        #expect(UploadConstraints.image.rejection(
            forSize: 1_000, mimeType: "image/png", header: png) == nil)
    }

    /// Le type annoncé et l'extension sont sous le contrôle de l'émetteur.
    /// Le contenu ne l'est pas.
    @Test("Un fichier annoncé PNG dont le contenu ne l'est pas est un incident")
    func contentTypeMismatchIsIncident() {
        let notPNG: [UInt8] = [0x4D, 0x5A, 0x90, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        let rejection = UploadConstraints.image.rejection(
            forSize: 1_000, mimeType: "image/png", header: notPNG)

        #expect(rejection == .contentTypeMismatch)
        #expect(rejection?.isSecurityIncident == true)
    }

    @Test("Un type sans signature connue n'est pas refusé par ignorance")
    func unknownSignaturePasses() {
        // Refuser ce qu'on ne sait pas reconnaître bloquerait des formats
        // légitimes sans rien sécuriser.
        #expect(MagicByteValidator.matches(declaredMIME: "image/heic",
                                           header: [0x00, 0x01, 0x02]))
    }

    @Test("Un en-tête tronqué ne valide pas une signature")
    func truncatedHeaderFails() {
        #expect(!MagicByteValidator.matches(declaredMIME: "image/png",
                                            header: [0x89, 0x50]))
    }

    @Test("Le document financier exige le chiffrement")
    func financialDocumentRequiresEncryption() {
        #expect(UploadConstraints.financialDocument.requiresEncryption)
        #expect(!UploadConstraints.image.requiresEncryption)
    }

    /// §22.9 — le texte passe avant le média.
    @Test("La priorité place le texte avant les médias")
    func textOutranksMedia() {
        #expect(UploadPriority.critical < UploadPriority.text)
        #expect(UploadPriority.text < UploadPriority.thumbnail)
        #expect(UploadPriority.thumbnail < UploadPriority.media)
        #expect(UploadPriority.media < UploadPriority.deferred)
    }

    // MARK: - Enveloppe (§24, §25)

    private func metadata(schema: Int = 1, serverTime: Date = Date()) -> ResponseMetadata {
        ResponseMetadata(requestID: "r-1", correlationID: "c-1",
                         serverTime: serverTime, schemaVersion: schema)
    }

    @Test("Un schéma plus récent que le client n'est pas interprété")
    func futureSchemaIsRejected() {
        // Appliquer une charge dont on ignore les champs les perd en silence.
        #expect(!metadata(schema: 99).isInterpretable)
        #expect(metadata(schema: 1).isInterpretable)
    }

    @Test("Le décalage d'horloge se mesure par rapport au serveur")
    func clockSkewIsMeasured() {
        let past = metadata(serverTime: Date(timeIntervalSinceNow: -120))
        #expect(past.clockSkew() > 100)
    }

    @Test("Une page annonçant une suite sans curseur est incohérente")
    func hasMoreWithoutCursorIsInconsistent() {
        // Le client boucle ou s'arrête — les deux sont faux.
        let broken = SyncEnvelope<String>(
            metadata: metadata(), cursor: nil, hasMore: true, items: [])
        #expect(!broken.isSelfConsistent)

        let sound = SyncEnvelope<String>(
            metadata: metadata(), cursor: "next", hasMore: true, items: ["a"])
        #expect(sound.isSelfConsistent)
    }

    @Test("La dernière page est cohérente sans curseur")
    func lastPageIsConsistent() {
        let last = SyncEnvelope<String>(
            metadata: metadata(), cursor: nil, hasMore: false, items: ["a"])
        #expect(last.isSelfConsistent)
    }

    // MARK: - Routes (§24)

    @Test("Toute mutation exige une clé d'idempotence")
    func everyMutationIsIdempotent() {
        for endpoint in SyncEndpoint.allCases where endpoint.isMutation {
            #expect(endpoint.requiresIdempotencyKey,
                    "\(endpoint.path) mute sans exiger d'idempotence")
        }
    }

    @Test("La route de statut est sûre pour lever une issue inconnue")
    func statusEndpointIsRequerySafe() {
        // C'est celle qu'on appelle *au lieu* de rejouer une mutation.
        #expect(SyncEndpoint.financialObjectStatus.isRequerySafe)
        #expect(!SyncEndpoint.sendMessage.isRequerySafe)
    }

    @Test("Une route interrogeable ne mute jamais")
    func requerySafeNeverMutates() {
        for endpoint in SyncEndpoint.allCases where endpoint.isRequerySafe {
            #expect(!endpoint.isMutation)
        }
    }

    // MARK: - Télémétrie (§26)

    @Test("Chaque événement porte un nom stable et distinct")
    func telemetryNamesAreUnique() {
        let events: [SyncTelemetryEvent] = [
            .syncStarted(stream: "s"), .syncCompleted(stream: "s", applied: 1, duration: 1),
            .syncFailed(stream: "s", code: "x"), .cursorGap(stream: "s", expected: 1, received: 3),
            .cursorInvalid(stream: "s"), .cursorCommitted(stream: "s", sequence: 1),
            .outboxQueued(type: "t", queueDepth: 1), .outboxRetry(type: "t", attempt: 1, delay: 1),
            .outboxDeadLetter(reasonKey: "r", attempts: 3), .mqttConnected(transport: "mqtt"),
            .mqttDisconnected(codeKey: "k"),
            .mqttGapDetected(topicHash: "h", expected: 1, received: 3),
            .deviceRevoked(deviceIDHash: "h"), .sessionExpired,
            .cachePurged(scope: "chat", itemCount: 1),
            .reconciliationStarted(objectIDHash: "h"),
            .reconciliationCompleted(objectIDHash: "h", outcomeKey: "o")
        ]
        #expect(Set(events.map(\.name)).count == events.count)
    }

    @Test("Un trou de curseur est une alerte, pas une information")
    func cursorGapAlerts() {
        #expect(SyncTelemetryEvent.cursorGap(stream: "s", expected: 5, received: 9)
            .severity == .alert)
        #expect(SyncTelemetryEvent.syncStarted(stream: "s").severity == .info)
    }

    @Test("Un trou rapporte combien d'événements manquent")
    func gapReportsMissingCount() {
        let fields = SyncTelemetryEvent
            .cursorGap(stream: "s", expected: 5, received: 9).fields
        #expect(fields["missing"] == "4")
    }

    /// §26 — la télémétrie ne doit jamais porter de texte libre.
    @Test("Le code de télémétrie n'emprunte jamais le texte de l'erreur")
    func telemetryCodeCarriesNoFreeText() {
        let secretish = SyncError.malformedPayload(reason: "token=abc123 secret")
        #expect(secretish.telemetryCode == "malformed_payload")
        #expect(!secretish.telemetryCode.contains("abc123"))

        let coded = SyncError.permanentFailure(code: "carte 4111111111111111")
        #expect(coded.telemetryCode == "permanent_failure")
        #expect(!coded.telemetryCode.contains("4111"))
    }

    @Test("Le contexte de trace hache ce qui est rejouable")
    func traceHashesReplayableValues() {
        let trace = SyncTraceContext(
            correlationID: CorrelationId(value: "c-1"),
            idempotencyKey: "idem-secret",
            deviceID: "device-secret"
        )
        // La corrélation reste lisible : elle sert à recouper, elle n'ouvre rien.
        #expect(trace.fields["correlation_id"] == "c-1")
        // La clé d'idempotence et l'appareil ne sortent jamais en clair.
        #expect(trace.idempotencyKeyHash != "idem-secret")
        #expect(trace.deviceIDHash != "device-secret")
        #expect(trace.fields.values.allSatisfy { !$0.contains("secret") })
    }
}
