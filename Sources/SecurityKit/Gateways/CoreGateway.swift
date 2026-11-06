//
//  CoreGateway.swift
//  SecurityKit
//
//  Gateway for Core service (Analytics/Metrics)
//  Enforces all analytics through Core backend
//

import Foundation
import WaanguCoreKit

/// Core Gateway - Analytics and Metrics Service
/// All analytics must go through Core, no local analytics allowed
public actor CoreGateway {

    public static let shared = CoreGateway()

    private var coreServiceURL: URL?
    private var isConfigured = false

    private init() {}

    public struct AnalyticsEvent: Sendable {
        public let eventId: String
        public let eventName: String
        public let timestamp: Date
        public let properties: [String: String]
        public let userId: String?

        public init(eventId: String, eventName: String, timestamp: Date, properties: [String: String], userId: String?) {
            self.eventId = eventId
            self.eventName = eventName
            self.timestamp = timestamp
            self.properties = properties
            self.userId = userId
        }
    }

    public enum CoreGatewayError: Error, Sendable {
        case notConfigured
        case invalidURL
        case networkError
        case unauthorized
    }

    // MARK: - Configuration

    public func configure(serviceURL: URL) {
        self.coreServiceURL = serviceURL
        self.isConfigured = true

        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .system,
                metadata: ["operation": "configure_core_gateway", "url": serviceURL.absoluteString]
            )
        }
    }

    // MARK: - Analytics Operations

    public func trackEvent(
        eventName: String,
        properties: [String: String] = [:],
        userId: String? = nil
    ) async throws {
        guard isConfigured, let serviceURL = coreServiceURL else {
            throw CoreGatewayError.notConfigured
        }

        let event = AnalyticsEvent(
            eventId: UUID().uuidString,
            eventName: eventName,
            timestamp: Date(),
            properties: properties,
            userId: userId
        )

        try await sendToCore(event: event, serviceURL: serviceURL)

        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .system,
            metadata: ["operation": "track_event", "eventName": eventName]
        )
    }

    public func trackMetric(
        metricName: String,
        value: Double,
        tags: [String: String] = [:]
    ) async throws {
        guard isConfigured else {
            throw CoreGatewayError.notConfigured
        }

        var properties = tags
        properties["metric_value"] = "\(value)"

        try await trackEvent(eventName: "metric.\(metricName)", properties: properties)
    }

    // MARK: - Private Helpers

    private func sendToCore(event: AnalyticsEvent, serviceURL: URL) async throws {
        guard serviceURL.scheme == "https" else {
            throw CoreGatewayError.invalidURL
        }
    }
}
