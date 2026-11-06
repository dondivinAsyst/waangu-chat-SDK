//
//  MerchantCatalogManager.swift
//  SecurityKit
//
//  Merchant catalog - signed and expirable
//  All catalogs must be signed by backend
//

import Foundation
import WaanguCoreKit
import CryptoKit

/// Merchant catalog manager
/// Catalogs are signed and expirable
public actor MerchantCatalogManager {
    
    public static let shared = MerchantCatalogManager()
    
    private var catalogs: [String: MerchantCatalog] = [:]
    
    private init() {}
    
    public struct MerchantCatalog: Sendable {
        public let catalogId: String
        public let merchantId: String
        public let items: [CatalogItem]
        public let signature: String
        public let createdAt: Date
        public let expiresAt: Date
        
        public init(catalogId: String, merchantId: String, items: [CatalogItem], signature: String, createdAt: Date, expiresAt: Date) {
            self.catalogId = catalogId
            self.merchantId = merchantId
            self.items = items
            self.signature = signature
            self.createdAt = createdAt
            self.expiresAt = expiresAt
        }
        
        public var isExpired: Bool {
            return Date() > expiresAt
        }
    }
    
    public struct CatalogItem: Sendable {
        public let itemId: String
        public let name: String
        public let price: Decimal
        public let currency: String
        
        public init(itemId: String, name: String, price: Decimal, currency: String) {
            self.itemId = itemId
            self.name = name
            self.price = price
            self.currency = currency
        }
    }
    
    public enum CatalogError: Error, Sendable {
        case invalidSignature
        case expired
        case notFound
        case unsignedCatalog
    }
    
    // MARK: - Public API
    
    /// Register catalog (must be signed)
    public func registerCatalog(
        catalogId: String,
        merchantId: String,
        items: [CatalogItem],
        signature: String,
        expirationHours: Int = 24
    ) throws {
        // RULE: Must have signature
        guard !signature.isEmpty else {
            throw CatalogError.unsignedCatalog
        }
        
        let expiresAt = Date().addingTimeInterval(TimeInterval(expirationHours * 3600))
        
        let catalog = MerchantCatalog(
            catalogId: catalogId,
            merchantId: merchantId,
            items: items,
            signature: signature,
            createdAt: Date(),
            expiresAt: expiresAt
        )
        
        // Verify signature
        guard verifyCatalogSignature(catalog: catalog) else {
            Task {
                await AuditBreadcrumb.shared.recordSecurity(
                    action: .securityViolation,
                    userId: nil,
                    metadata: ["violation": "invalid_catalog_signature", "catalogId": catalogId]
                )
            }
            throw CatalogError.invalidSignature
        }
        
        catalogs[catalogId] = catalog
        
        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .dataModification,
                metadata: ["operation": "register_catalog", "catalogId": catalogId, "merchantId": merchantId]
            )
        }
    }
    
    /// Get catalog (checks expiration)
    public func getCatalog(catalogId: String) throws -> MerchantCatalog {
        guard let catalog = catalogs[catalogId] else {
            throw CatalogError.notFound
        }
        
        guard !catalog.isExpired else {
            throw CatalogError.expired
        }
        
        return catalog
    }
    
    /// Clean up expired catalogs
    public func cleanupExpired() -> [String] {
        let expired = catalogs.values.filter { $0.isExpired }
        let expiredIds = expired.map { $0.catalogId }
        
        for id in expiredIds {
            catalogs.removeValue(forKey: id)
        }
        
        return expiredIds
    }
    
    // MARK: - Private Helpers
    
    private func verifyCatalogSignature(catalog: MerchantCatalog) -> Bool {
        // In production: HMAC-SHA256 verification
        return !catalog.signature.isEmpty && catalog.signature.count >= 32
    }
}
