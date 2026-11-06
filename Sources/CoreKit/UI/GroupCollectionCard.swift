//
//  GroupCollectionCard.swift
//  CoreKit
//
//  Group collection/tontine action card
//  Backend-driven group collection UI
//

import Foundation

/// Group collection/tontine action card
public struct GroupCollectionCard: Sendable {
    public let cardId: String
    public let title: String
    public let groupName: String
    public let targetAmount: Decimal
    public let currentAmount: Decimal
    public let currency: String
    public let participants: [Participant]
    public let deadline: Date?
    public let collectionType: CollectionType
    
    public init(cardId: String, title: String, groupName: String, targetAmount: Decimal, currentAmount: Decimal, currency: String, participants: [Participant], deadline: Date?, collectionType: CollectionType) {
        self.cardId = cardId
        self.title = title
        self.groupName = groupName
        self.targetAmount = targetAmount
        self.currentAmount = currentAmount
        self.currency = currency
        self.participants = participants
        self.deadline = deadline
        self.collectionType = collectionType
    }
    
    public struct Participant: Sendable {
        public let userId: String
        public let name: String
        public let contributed: Decimal
        public let hasPaid: Bool
        
        public init(userId: String, name: String, contributed: Decimal, hasPaid: Bool) {
            self.userId = userId
            self.name = name
            self.contributed = contributed
            self.hasPaid = hasPaid
        }
    }
    
    public enum CollectionType: String, Sendable {
        case tontine
        case groupBuy
        case giftCollection
        case eventFunding
    }
}
