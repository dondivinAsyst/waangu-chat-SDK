import Foundation

/// Action Cards System for conversational UI
/// Provides structured action cards for user interactions
public actor ActionCardsSystem {
    
    public static let shared = ActionCardsSystem()
    
    private var registeredCards: [String: ActionCard] = [:]
    
    private init() {}
    
    public struct ActionCard: Sendable {
        public let id: String
        public let title: String
        public let description: String
        public let actions: [CardAction]
        public let metadata: [String: String]
        public let createdAt: Date
        
        public init(
            id: String = UUID().uuidString,
            title: String,
            description: String,
            actions: [CardAction],
            metadata: [String: String] = [:]
        ) {
            self.id = id
            self.title = title
            self.description = description
            self.actions = actions
            self.metadata = metadata
            self.createdAt = Date()
        }
    }
    
    public struct CardAction: Sendable {
        public let id: String
        public let label: String
        public let actionType: ActionType
        public let payload: [String: String]
        
        public init(
            id: String = UUID().uuidString,
            label: String,
            actionType: ActionType,
            payload: [String: String] = [:]
        ) {
            self.id = id
            self.label = label
            self.actionType = actionType
            self.payload = payload
        }
    }
    
    public enum ActionType: String, Sendable {
        case primary = "PRIMARY"
        case secondary = "SECONDARY"
        case destructive = "DESTRUCTIVE"
        case link = "LINK"
    }
    
    /// Registers an action card
    public func registerCard(_ card: ActionCard) {
        registeredCards[card.id] = card
    }
    
    /// Gets a card by ID
    public func getCard(_ id: String) -> ActionCard? {
        registeredCards[id]
    }
    
    /// Creates a payment action card
    public func createPaymentCard(
        amount: String,
        recipient: String,
        description: String
    ) -> ActionCard {
        let card = ActionCard(
            title: "Payment Request",
            description: description,
            actions: [
                CardAction(
                    label: "Confirm Payment",
                    actionType: .primary,
                    payload: ["amount": amount, "recipient": recipient]
                ),
                CardAction(
                    label: "Cancel",
                    actionType: .secondary,
                    payload: [:]
                )
            ],
            metadata: ["type": "payment", "amount": amount]
        )
        registerCard(card)
        return card
    }
    
    /// Creates a confirmation action card
    public func createConfirmationCard(
        title: String,
        message: String,
        confirmLabel: String = "Confirm",
        cancelLabel: String = "Cancel"
    ) -> ActionCard {
        let card = ActionCard(
            title: title,
            description: message,
            actions: [
                CardAction(
                    label: confirmLabel,
                    actionType: .primary,
                    payload: [:]
                ),
                CardAction(
                    label: cancelLabel,
                    actionType: .secondary,
                    payload: [:]
                )
            ]
        )
        registerCard(card)
        return card
    }
    
    /// Creates a selection action card
    public func createSelectionCard(
        title: String,
        options: [String]
    ) -> ActionCard {
        let actions = options.map { option in
            CardAction(
                label: option,
                actionType: .primary,
                payload: ["selection": option]
            )
        }
        
        let card = ActionCard(
            title: title,
            description: "Select an option",
            actions: actions
        )
        registerCard(card)
        return card
    }
    
    /// Gets all registered cards
    public func getAllCards() -> [ActionCard] {
        Array(registeredCards.values)
    }
    
    /// Removes a card
    public func removeCard(_ id: String) {
        registeredCards.removeValue(forKey: id)
    }
}
