//
//  MiniSurfaceValidator.swift
//  CoreKit
//
//  Validates mini-surfaces are signed and expirable
//  RULE: Mini-surfaces signées et expirables. Pas de mini-program local métier.

import Foundation
import WaanguCoreKit
import CryptoKit

public actor MiniSurfaceValidator {
    
    public static let shared = MiniSurfaceValidator()
    
    private var loadedSurfaces: [String: MiniSurface] = [:]
    private let signingKey: SymmetricKey
    
    private init() {
        self.signingKey = SymmetricKey(size: .bits256)
    }
    
    // MARK: - Mini-Surface Loading
    
    /// Loads and validates a mini-surface
    /// RULE: Mini-surfaces signées et expirables
    public func loadMiniSurface(_ encoded: String) async throws -> MiniSurface {
        
        // Decode surface
        let surface = try decodeSurface(encoded)
        
        // Verify signature
        guard try verifySignature(surface) else {
            throw MiniSurfaceError.invalidSignature
        }
        
        // Check expiration
        guard surface.expiresAt > Date() else {
            throw MiniSurfaceError.expired(expiresAt: surface.expiresAt)
        }
        
        // RULE: Pas de mini-program local métier
        try validateNotLocalBusinessLogic(surface)
        
        // Store loaded surface
        loadedSurfaces[surface.id] = surface
        
        // Audit
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .security,
            metadata: [
                "action": "mini_surface_loaded",
                "surface_id": surface.id,
                "type": surface.type.rawValue
            ],
            severity: .info
        )
        
        return surface
    }
    
    // MARK: - Business Logic Validation
    
    /// RULE: Pas de mini-program local métier
    private func validateNotLocalBusinessLogic(_ surface: MiniSurface) throws {
        
        // Check for forbidden business logic patterns
        let forbiddenPatterns = [
            "calculatePrice",
            "applyDiscount",
            "processPayment",
            "validateTransaction",
            "computeTax",
            "calculateFee"
        ]
        
        for pattern in forbiddenPatterns {
            if surface.content.contains(pattern) {
                throw MiniSurfaceError.localBusinessLogicForbidden(pattern: pattern)
            }
        }
        
        // Mini-surfaces must be display-only or call backend
        guard surface.type == .displayOnly || surface.type == .backendDriven else {
            throw MiniSurfaceError.localBusinessLogicForbidden(pattern: "non-display surface type")
        }
    }
    
    // MARK: - Signature Verification
    
    private func verifySignature(_ surface: MiniSurface) throws -> Bool {
        let data = try encodeForSigning(surface)
        let expectedSignature = HMAC<SHA256>.authenticationCode(for: data, using: signingKey)
        
        guard let signatureData = Data(base64Encoded: surface.signature) else {
            return false
        }
        
        return Data(expectedSignature) == signatureData
    }
    
    private func encodeForSigning(_ surface: MiniSurface) throws -> Data {
        let signingData = "\(surface.id):\(surface.type.rawValue):\(surface.content):\(surface.expiresAt.timeIntervalSince1970)"
        return Data(signingData.utf8)
    }
    
    // MARK: - Encoding/Decoding
    
    private func decodeSurface(_ encoded: String) throws -> MiniSurface {
        guard let data = Data(base64Encoded: encoded) else {
            throw MiniSurfaceError.invalidFormat
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MiniSurface.self, from: data)
    }
    
    // MARK: - Cleanup
    
    public func cleanupExpiredSurfaces() async {
        let now = Date()
        loadedSurfaces = loadedSurfaces.filter { $0.value.expiresAt > now }
    }
    
    // MARK: - Types
    
    public struct MiniSurface: Codable {
        public let id: String
        public let type: SurfaceType
        public let content: String
        public let signature: String
        public let issuedAt: Date
        public let expiresAt: Date
        
        public init(id: String, type: SurfaceType, content: String, signature: String, issuedAt: Date, expiresAt: Date) {
            self.id = id
            self.type = type
            self.content = content
            self.signature = signature
            self.issuedAt = issuedAt
            self.expiresAt = expiresAt
        }
    }
    
    public enum SurfaceType: String, Codable {
        case displayOnly
        case backendDriven
        case interactive
    }
    
    public enum MiniSurfaceError: Error, LocalizedError {
        case invalidSignature
        case invalidFormat
        case expired(expiresAt: Date)
        case localBusinessLogicForbidden(pattern: String)
        
        public var errorDescription: String? {
            switch self {
            case .invalidSignature:
                return "Mini-surface signature is invalid"
            case .invalidFormat:
                return "Mini-surface format is invalid"
            case .expired(let expiresAt):
                return "Mini-surface expired at \(expiresAt)"
            case .localBusinessLogicForbidden(let pattern):
                return "Local business logic forbidden in mini-surface: \(pattern)"
            }
        }
    }
}
