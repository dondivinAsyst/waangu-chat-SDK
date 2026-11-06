//
//  JacksonGateway.swift
//  SecurityKit
//
//  Gateway for Jackson service (Notifications)
//  Enforces all notifications through Jackson backend
//

import Foundation
import WaanguCoreKit

/// Jackson Gateway - Notification Service
/// All notifications must go through Jackson
public actor JacksonGateway {
    
    public static let shared = JacksonGateway()
    
    private var jacksonServiceURL: URL?
    private var isConfigured = false
    
    private init() {}
    
    public struct NotificationRequest: Sendable {
        public let notificationId: String
        public let userId: String
        public let title: String
        public let body: String
        public let type: NotificationType
        public let timestamp: Date
        public let data: [String: String]
        
        public init(notificationId: String, userId: String, title: String, body: String, type: NotificationType, timestamp: Date, data: [String: String]) {
            self.notificationId = notificationId
            self.userId = userId
            self.title = title
            self.body = body
            self.type = type
            self.timestamp = timestamp
            self.data = data
        }
    }
    
    public enum NotificationType: String, Sendable {
        case message
        case payment
        case alert
        case reminder
        case system
    }
    
    public enum JacksonError: Error, Sendable {
        case notConfigured
        case invalidURL
        case networkError
    }
    
    // MARK: - Configuration
    
    public func configure(serviceURL: URL) {
        self.jacksonServiceURL = serviceURL
        self.isConfigured = true
        
        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .system,
                metadata: ["operation": "configure_jackson_gateway", "url": serviceURL.absoluteString]
            )
        }
    }
    
    // MARK: - Notification Operations
    
    public func sendNotification(
        userId: String,
        title: String,
        body: String,
        type: NotificationType,
        data: [String: String] = [:]
    ) async throws {
        guard isConfigured, let serviceURL = jacksonServiceURL else {
            throw JacksonError.notConfigured
        }
        
        let notification = NotificationRequest(
            notificationId: UUID().uuidString,
            userId: userId,
            title: title,
            body: body,
            type: type,
            timestamp: Date(),
            data: data
        )
        
        try await sendToJackson(notification: notification, serviceURL: serviceURL)
        
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .network,
            metadata: ["operation": "send_notification", "type": type.rawValue, "userId": userId]
        )
    }
    
    // MARK: - Private Helpers
    
    private func sendToJackson(notification: NotificationRequest, serviceURL: URL) async throws {
        // In production: actual HTTP request to Jackson service
    }
}
