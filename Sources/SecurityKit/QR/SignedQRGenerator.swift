//
//  SignedQRGenerator.swift
//  CoreKit
//
//  Generates signed, expiring, nonced QR codes
//  RULE: QR signé, expirant, noncé. Aucun QR faible.

import Foundation
import WaanguCoreKit
import CryptoKit

public actor SignedQRGenerator {
    
    public static let shared = SignedQRGenerator()
    
    private var activeQRCodes: [String: SignedQRCode] = [:]

    /// Trousseau porteur de la clé de signature. `nil` tant que `configure` n'a
    /// pas été appelé — l'acteur refuse alors de signer.
    private var keychain: (any KeychainStoreProtocol)?

    /// Clé chargée, mise en cache pour éviter un accès trousseau par QR.
    private var cachedSigningKey: SymmetricKey?

    private static let keychainKey = "com.waangu.qr.signing-key"

    private init() {}

    // MARK: - Configuration

    /// Installe le trousseau porteur de la clé de signature.
    ///
    /// Obligatoire avant toute génération. Auparavant la clé était produite par
    /// `SymmetricKey(size: .bits256)` dans l'initialiseur, donc régénérée à chaque
    /// lancement : un QR signé avant un relaunch échouait à la vérification après,
    /// puisque la clé qui l'avait signé n'existait plus. Le commentaire du code
    /// d'origine — « In production, load from secure enclave or keychain » — le
    /// reconnaissait.
    public func configure(keychain: any KeychainStoreProtocol) {
        self.keychain = keychain
        self.cachedSigningKey = nil
    }

    /// Charge la clé, ou la crée au premier usage et la persiste.
    ///
    /// - Throws: `QRSigningKeyError.notConfigured` si aucun trousseau n'est
    ///   installé. Générer une clé volatile en repli reproduirait exactement le
    ///   défaut corrigé ici — mieux vaut refuser de signer.
    private func signingKey() async throws -> SymmetricKey {
        if let cachedSigningKey { return cachedSigningKey }

        guard let keychain else { throw QRSigningKeyError.notConfigured }

        if let existing = try await keychain.getData(forKey: Self.keychainKey),
           existing.count >= 32 {
            let key = SymmetricKey(data: existing)
            cachedSigningKey = key
            return key
        }

        // Première utilisation sur cet appareil : créer et persister.
        let key = SymmetricKey(size: .bits256)
        let material = key.withUnsafeBytes { Data($0) }
        try await keychain.saveData(material, forKey: Self.keychainKey)
        cachedSigningKey = key
        return key
    }

    /// Détruit la clé — déconnexion, révocation d'appareil.
    /// Tous les QR déjà émis deviennent invérifiables, ce qui est l'effet voulu.
    public func destroySigningKey() async throws {
        try await keychain?.remove(forKey: Self.keychainKey)
        cachedSigningKey = nil
    }
    
    // MARK: - QR Generation
    
    public func generateQR(
        payload: QRPayload,
        expiresIn: TimeInterval = 300 // 5 minutes default
    ) async throws -> SignedQRCode {
        
        // Validate payload strength
        try validatePayloadStrength(payload)
        
        // Generate nonce
        let nonce = generateNonce()
        
        // Calculate expiration
        let expiresAt = Date().addingTimeInterval(expiresIn)
        
        // Create QR data
        let qrData = QRData(
            payload: payload,
            nonce: nonce,
            issuedAt: Date(),
            expiresAt: expiresAt,
            version: "1.0"
        )
        
        // Sign QR
        let signature = try await signQRData(qrData)
        
        let signedQR = SignedQRCode(
            id: UUID().uuidString,
            data: qrData,
            signature: signature,
            encodedString: try encodeQR(qrData, signature: signature)
        )
        
        // Store active QR
        activeQRCodes[signedQR.id] = signedQR
        
        // Audit
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .security,
            metadata: [
                "action": "qr_generated",
                "qr_id": signedQR.id,
                "type": payload.type.rawValue,
                "expires_in": "\(expiresIn)",
                "nonce": nonce
            ],
            severity: .info
        )
        
        return signedQR
    }
    
    // MARK: - QR Validation
    
    public func validateQR(_ encodedString: String) async throws -> QRData {
        
        // Decode QR
        let (qrData, signature) = try decodeQR(encodedString)
        
        // Check expiration
        guard qrData.expiresAt > Date() else {
            throw QRError.expired(expiresAt: qrData.expiresAt)
        }
        
        // Verify signature
        guard try await verifySignature(qrData: qrData, signature: signature) else {
            throw QRError.invalidSignature
        }
        
        // Check nonce uniqueness (replay protection)
        try await checkNonceUniqueness(qrData.nonce)
        
        // Validate payload strength
        try validatePayloadStrength(qrData.payload)
        
        // Audit
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .security,
            metadata: [
                "action": "qr_validated",
                "type": qrData.payload.type.rawValue,
                "nonce": qrData.nonce
            ],
            severity: .info
        )
        
        return qrData
    }
    
    // MARK: - Weak QR Detection
    
    private func validatePayloadStrength(_ payload: QRPayload) throws {
        
        // RULE: Aucun QR faible
        
        switch payload.type {
        case .payment:
            // Payment QR must have amount and recipient
            guard let amount = payload.data["amount"], !amount.isEmpty else {
                throw QRError.weakQR(reason: "Payment QR missing amount")
            }
            guard let recipient = payload.data["recipient"], !recipient.isEmpty else {
                throw QRError.weakQR(reason: "Payment QR missing recipient")
            }
            
        case .profile:
            // Profile QR must have userId
            guard let userId = payload.data["userId"], !userId.isEmpty else {
                throw QRError.weakQR(reason: "Profile QR missing userId")
            }
            
        case .chatRoom:
            // Chat room QR must have roomId
            guard let roomId = payload.data["roomId"], !roomId.isEmpty else {
                throw QRError.weakQR(reason: "Chat room QR missing roomId")
            }
            
        case .merchant:
            // Merchant QR must have merchantId and location
            guard let merchantId = payload.data["merchantId"], !merchantId.isEmpty else {
                throw QRError.weakQR(reason: "Merchant QR missing merchantId")
            }
            guard let location = payload.data["location"], !location.isEmpty else {
                throw QRError.weakQR(reason: "Merchant QR missing location")
            }
        }
        
        // Check minimum data size
        let dataSize = payload.data.values.joined().count
        guard dataSize >= 10 else {
            throw QRError.weakQR(reason: "QR payload too small: \(dataSize) bytes")
        }
    }
    
    // MARK: - Cryptographic Operations
    
    /// Sérialisation canonique du contenu signé.
    ///
    /// `.sortedKeys` est indispensable : sans lui, rien ne garantit que deux
    /// encodages du même `QRData` produisent le même octet, et une signature
    /// vérifiée sur un ordre de clés différent échoue sans raison apparente.
    private func canonicalData(_ qrData: QRData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(qrData)
    }

    private func signQRData(_ qrData: QRData) async throws -> String {
        let key = try await signingKey()
        let signature = HMAC<SHA256>.authenticationCode(for: try canonicalData(qrData), using: key)
        return Data(signature).base64EncodedString()
    }
    
    private func verifySignature(qrData: QRData, signature: String) async throws -> Bool {
        let key = try await signingKey()

        guard let signatureData = Data(base64Encoded: signature) else {
            return false
        }

        // Comparaison à temps constant. Un `==` sur deux `Data` s'arrête au
        // premier octet divergent, ce qui laisse déduire la position de l'erreur
        // et forger une signature octet par octet.
        return HMAC<SHA256>.isValidAuthenticationCode(
            signatureData,
            authenticating: try canonicalData(qrData),
            using: key
        )
    }
    
    private func generateNonce() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).base64EncodedString()
    }
    
    private func checkNonceUniqueness(_ nonce: String) async throws {
        // Check if nonce was already used
        let usedNonces = activeQRCodes.values.map { $0.data.nonce }
        
        if usedNonces.contains(nonce) {
            throw QRError.nonceReused(nonce: nonce)
        }
    }
    
    // MARK: - Encoding/Decoding
    
    private func encodeQR(_ qrData: QRData, signature: String) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let container = QRContainer(data: qrData, signature: signature)
        let jsonData = try encoder.encode(container)
        return jsonData.base64EncodedString()
    }
    
    private func decodeQR(_ encodedString: String) throws -> (QRData, String) {
        guard let jsonData = Data(base64Encoded: encodedString) else {
            throw QRError.invalidFormat
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let container = try decoder.decode(QRContainer.self, from: jsonData)
        return (container.data, container.signature)
    }
    
    // MARK: - Cleanup
    
    public func cleanupExpiredQRs() async {
        let now = Date()
        activeQRCodes = activeQRCodes.filter { $0.value.data.expiresAt > now }
    }
    
    public func getActiveQRCount() -> Int {
        activeQRCodes.count
    }
    
    // MARK: - Types
    
    public struct SignedQRCode {
        public let id: String
        public let data: QRData
        public let signature: String
        public let encodedString: String
    }
    
    public struct QRData: Codable {
        public let payload: QRPayload
        public let nonce: String
        public let issuedAt: Date
        public let expiresAt: Date
        public let version: String
    }
    
    public struct QRPayload: Codable {
        public let type: QRType
        public let data: [String: String]
        
        public init(type: QRType, data: [String: String]) {
            self.type = type
            self.data = data
        }
    }
    
    public enum QRType: String, Codable {
        case payment
        case profile
        case chatRoom
        case merchant
    }
    
    private struct QRContainer: Codable {
        let data: QRData
        let signature: String
    }
    
    public enum QRError: Error, LocalizedError {
        case expired(expiresAt: Date)
        case invalidSignature
        case invalidFormat
        case weakQR(reason: String)
        case nonceReused(nonce: String)
        
        public var errorDescription: String? {
            switch self {
            case .expired(let expiresAt):
                return "QR code expired at \(expiresAt)"
            case .invalidSignature:
                return "QR code signature is invalid"
            case .invalidFormat:
                return "QR code format is invalid"
            case .weakQR(let reason):
                return "Weak QR code rejected: \(reason)"
            case .nonceReused(let nonce):
                return "QR nonce was already used: \(nonce)"
            }
        }
    }
}


// MARK: - Erreurs de clé

public enum QRSigningKeyError: Error, Sendable, Equatable {
    /// Aucun trousseau installé — `configure(keychain:)` n'a pas été appelé.
    ///
    /// Refuser de signer plutôt que produire une clé volatile : un QR signé avec
    /// une clé qui disparaît au relaunch est un QR qui ne se vérifiera jamais.
    case notConfigured
}
