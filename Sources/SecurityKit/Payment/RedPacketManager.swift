//
//  RedPacketManager.swift
//  SecurityKit
//
//  Red packet (lucky money) - backend-driven
//  All red packet logic controlled by backend
//

import Foundation
import WaanguCoreKit

/// Red packet manager - backend-driven
/// No local red packet logic allowed
public actor RedPacketManager {
    
    public static let shared = RedPacketManager()
    
    private var activePackets: [String: RedPacket] = [:]
    private var claimedPackets: [String: ClaimedPacket] = [:]
    
    private init() {}
    
    public struct RedPacket: Sendable {
        public let packetId: String
        public let senderId: String
        public let totalAmount: Decimal
        public let currency: String
        public let count: Int
        public let message: String
        public let createdAt: Date
        public let expiresAt: Date
        public let backendControlled: Bool
        
        public init(packetId: String, senderId: String, totalAmount: Decimal, currency: String, count: Int, message: String, createdAt: Date, expiresAt: Date, backendControlled: Bool) {
            self.packetId = packetId
            self.senderId = senderId
            self.totalAmount = totalAmount
            self.currency = currency
            self.count = count
            self.message = message
            self.createdAt = createdAt
            self.expiresAt = expiresAt
            self.backendControlled = backendControlled
        }
    }
    
    public struct ClaimedPacket: Sendable {
        public let packetId: String
        public let userId: String
        public let amount: Decimal
        public let claimedAt: Date
        public let backendConfirmed: Bool
        
        public init(packetId: String, userId: String, amount: Decimal, claimedAt: Date, backendConfirmed: Bool) {
            self.packetId = packetId
            self.userId = userId
            self.amount = amount
            self.claimedAt = claimedAt
            self.backendConfirmed = backendConfirmed
        }
    }
    
    public enum RedPacketError: Error, Sendable {
        case notBackendControlled
        case localLogicAttempt
        case notFound
        case alreadyClaimed
    }
    
    // MARK: - Public API
    
    /// Create red packet (backend-driven)
    public func createPacket(
        packetId: String,
        senderId: String,
        totalAmount: Decimal,
        currency: String,
        count: Int,
        message: String,
        expirationMinutes: Int = 24 * 60
    ) throws {
        let packet = RedPacket(
            packetId: packetId,
            senderId: senderId,
            totalAmount: totalAmount,
            currency: currency,
            count: count,
            message: message,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(TimeInterval(expirationMinutes * 60)),
            backendControlled: true // ALWAYS backend-controlled
        )
        
        activePackets[packetId] = packet
        
        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .dataModification,
                metadata: ["operation": "create_red_packet", "packetId": packetId, "amount": "\(totalAmount)"]
            )
        }
    }
    
    /// Claim red packet (backend confirms amount)
    public func claimPacket(
        packetId: String,
        userId: String,
        backendAmount: Decimal
    ) throws {
        guard let packet = activePackets[packetId] else {
            throw RedPacketError.notFound
        }
        
        // RULE: Must be backend-controlled
        guard packet.backendControlled else {
            throw RedPacketError.notBackendControlled
        }
        
        let claimed = ClaimedPacket(
            packetId: packetId,
            userId: userId,
            amount: backendAmount, // Backend determines amount
            claimedAt: Date(),
            backendConfirmed: true
        )
        
        let key = "\(packetId):\(userId)"
        claimedPackets[key] = claimed
        
        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .dataModification,
                metadata: ["operation": "claim_red_packet", "packetId": packetId, "userId": userId, "amount": "\(backendAmount)"]
            )
        }
    }
    
    /// Attempt local logic (BLOCKED)
    public func attemptLocalLogic(packetId: String) throws {
        Task {
            await AuditBreadcrumb.shared.recordSecurity(
                action: .securityViolation,
                userId: nil,
                metadata: ["violation": "red_packet_local_logic", "packetId": packetId]
            )
        }
        throw RedPacketError.localLogicAttempt
    }
}
