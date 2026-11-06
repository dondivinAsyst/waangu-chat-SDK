//
//  ComplianceRenderer.swift
//  CoreKit
//
//  Deterministic compliance rendering
//  RULE: Compliance rendering deterministic

import Foundation
import WaanguCoreKit
import CryptoKit

public actor ComplianceRenderer {
    
    public static let shared = ComplianceRenderer()
    
    private var renderedCompliance: [String: RenderedCompliance] = [:]
    
    private init() {}
    
    // MARK: - Deterministic Rendering
    
    /// Renders compliance content deterministically
    /// RULE: Compliance rendering deterministic
    public func renderCompliance(
        contentId: String,
        complianceData: ComplianceData,
        renderingContext: RenderingContext
    ) async throws -> RenderedCompliance {
        
        // Compute deterministic hash
        let contentHash = try computeDeterministicHash(
            contentId: contentId,
            data: complianceData,
            context: renderingContext
        )
        
        // Check if already rendered with same hash
        if let existing = renderedCompliance[contentId],
           existing.contentHash == contentHash {
            return existing
        }
        
        // Render deterministically
        let rendered = try renderDeterministically(
            contentId: contentId,
            data: complianceData,
            context: renderingContext
        )
        
        let renderedCompliance = RenderedCompliance(
            contentId: contentId,
            contentHash: contentHash,
            rendered: rendered,
            renderingContext: renderingContext,
            renderedAt: Date()
        )
        
        self.renderedCompliance[contentId] = renderedCompliance
        
        // Audit
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .security,
            metadata: [
                "action": "compliance_rendered",
                "content_id": contentId,
                "content_hash": contentHash,
                "deterministic": "true"
            ],
            severity: .info
        )
        
        return renderedCompliance
    }
    
    // MARK: - Deterministic Hash
    
    private func computeDeterministicHash(
        contentId: String,
        data: ComplianceData,
        context: RenderingContext
    ) throws -> String {
        
        // Create deterministic string representation
        let components = [
            contentId,
            data.type.rawValue,
            data.content,
            context.locale,
            context.jurisdiction,
            String(context.version)
        ]
        
        let deterministicString = components.joined(separator: "|")
        let data = Data(deterministicString.utf8)
        let hash = SHA256.hash(data: data)
        
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Deterministic Rendering
    
    private func renderDeterministically(
        contentId: String,
        data: ComplianceData,
        context: RenderingContext
    ) throws -> String {
        
        // Render based on type
        switch data.type {
        case .termsOfService:
            return renderTermsOfService(data, context: context)
            
        case .privacyPolicy:
            return renderPrivacyPolicy(data, context: context)
            
        case .cookiePolicy:
            return renderCookiePolicy(data, context: context)
            
        case .gdprNotice:
            return renderGDPRNotice(data, context: context)
            
        case .consentForm:
            return renderConsentForm(data, context: context)
        }
    }
    
    private func renderTermsOfService(_ data: ComplianceData, context: RenderingContext) -> String {
        """
        TERMS OF SERVICE
        Jurisdiction: \(context.jurisdiction)
        Version: \(context.version)
        
        \(data.content)
        
        Last Updated: \(ISO8601DateFormatter().string(from: Date()))
        """
    }
    
    private func renderPrivacyPolicy(_ data: ComplianceData, context: RenderingContext) -> String {
        """
        PRIVACY POLICY
        Jurisdiction: \(context.jurisdiction)
        Version: \(context.version)
        
        \(data.content)
        
        Last Updated: \(ISO8601DateFormatter().string(from: Date()))
        """
    }
    
    private func renderCookiePolicy(_ data: ComplianceData, context: RenderingContext) -> String {
        """
        COOKIE POLICY
        Jurisdiction: \(context.jurisdiction)
        Version: \(context.version)
        
        \(data.content)
        
        Last Updated: \(ISO8601DateFormatter().string(from: Date()))
        """
    }
    
    private func renderGDPRNotice(_ data: ComplianceData, context: RenderingContext) -> String {
        """
        GDPR NOTICE
        Jurisdiction: \(context.jurisdiction)
        Version: \(context.version)
        
        \(data.content)
        
        Last Updated: \(ISO8601DateFormatter().string(from: Date()))
        """
    }
    
    private func renderConsentForm(_ data: ComplianceData, context: RenderingContext) -> String {
        """
        CONSENT FORM
        Jurisdiction: \(context.jurisdiction)
        Version: \(context.version)
        
        \(data.content)
        
        Last Updated: \(ISO8601DateFormatter().string(from: Date()))
        """
    }
    
    /// Validates rendering is deterministic
    public func validateDeterminism(
        contentId: String,
        complianceData: ComplianceData,
        renderingContext: RenderingContext
    ) async throws -> Bool {
        
        // Render twice
        let render1 = try await renderCompliance(
            contentId: contentId,
            complianceData: complianceData,
            renderingContext: renderingContext
        )
        
        let render2 = try await renderCompliance(
            contentId: contentId,
            complianceData: complianceData,
            renderingContext: renderingContext
        )
        
        // Hashes must match
        return render1.contentHash == render2.contentHash
    }
    
    // MARK: - Types
    
    public struct ComplianceData {
        public let type: ComplianceType
        public let content: String
        public let metadata: [String: String]
        
        public init(type: ComplianceType, content: String, metadata: [String: String] = [:]) {
            self.type = type
            self.content = content
            self.metadata = metadata
        }
    }
    
    public struct RenderingContext {
        public let locale: String
        public let jurisdiction: String
        public let version: Int
        
        public init(locale: String, jurisdiction: String, version: Int) {
            self.locale = locale
            self.jurisdiction = jurisdiction
            self.version = version
        }
    }
    
    public struct RenderedCompliance {
        public let contentId: String
        public let contentHash: String
        public let rendered: String
        public let renderingContext: RenderingContext
        public let renderedAt: Date
    }
    
    public enum ComplianceType: String {
        case termsOfService
        case privacyPolicy
        case cookiePolicy
        case gdprNotice
        case consentForm
    }
}
