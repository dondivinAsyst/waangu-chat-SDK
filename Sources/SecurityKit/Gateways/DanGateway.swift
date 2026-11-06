//
//  DanGateway.swift
//  SecurityKit
//
//  Gateway for Dan service (Storage/Media)
//  Enforces all storage operations through Dan backend
//

import Foundation
import WaanguCoreKit

/// Dan Gateway - Storage and Media Service
/// All storage operations must go through Dan
public actor DanGateway {
    
    public static let shared = DanGateway()
    
    private var danServiceURL: URL?
    private var isConfigured = false
    
    private init() {}
    
    public struct UploadRequest: Sendable {
        public let uploadId: String
        public let fileName: String
        public let fileSize: Int64
        public let mimeType: String
        public let userId: String
        public let timestamp: Date
        
        public init(uploadId: String, fileName: String, fileSize: Int64, mimeType: String, userId: String, timestamp: Date) {
            self.uploadId = uploadId
            self.fileName = fileName
            self.fileSize = fileSize
            self.mimeType = mimeType
            self.userId = userId
            self.timestamp = timestamp
        }
    }
    
    public struct UploadResult: Sendable {
        public let uploadId: String
        public let url: String
        public let expiresAt: Date?
        
        public init(uploadId: String, url: String, expiresAt: Date?) {
            self.uploadId = uploadId
            self.url = url
            self.expiresAt = expiresAt
        }
    }
    
    public enum DanError: Error, Sendable {
        case notConfigured
        case invalidURL
        case fileTooLarge
        case unsupportedFileType
        case networkError
    }
    
    // MARK: - Configuration
    
    public func configure(serviceURL: URL) {
        self.danServiceURL = serviceURL
        self.isConfigured = true
        
        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .system,
                metadata: ["operation": "configure_dan_gateway", "url": serviceURL.absoluteString]
            )
        }
    }
    
    // MARK: - Storage Operations
    
    public func uploadFile(
        fileName: String,
        fileSize: Int64,
        mimeType: String,
        userId: String,
        data: Data
    ) async throws -> UploadResult {
        guard isConfigured, let serviceURL = danServiceURL else {
            throw DanError.notConfigured
        }
        
        let request = UploadRequest(
            uploadId: UUID().uuidString,
            fileName: fileName,
            fileSize: fileSize,
            mimeType: mimeType,
            userId: userId,
            timestamp: Date()
        )
        
        let result = try await performUpload(request: request, data: data, serviceURL: serviceURL)
        
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .dataAccess,
            metadata: [
                "operation": "upload_file",
                "uploadId": request.uploadId,
                "fileName": fileName,
                "fileSize": "\(fileSize)"
            ]
        )
        
        return result
    }
    
    // MARK: - Private Helpers
    
    private func performUpload(request: UploadRequest, data: Data, serviceURL: URL) async throws -> UploadResult {
        // In production: actual HTTP request to Dan service
        return UploadResult(
            uploadId: request.uploadId,
            url: "\(serviceURL.absoluteString)/files/\(request.uploadId)",
            expiresAt: nil
        )
    }
}
