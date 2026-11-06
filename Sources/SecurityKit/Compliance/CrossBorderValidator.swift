//
//  CrossBorderValidator.swift
//  CoreKit
//
//  Validates cross-border context is mandatory
//  RULE: Cross-border context obligatoire

import Foundation

public actor CrossBorderValidator {
    
    public static let shared = CrossBorderValidator()
    
    private var crossBorderTransactions: [String: CrossBorderContext] = [:]
    
    private init() {}
    
    // MARK: - Cross-Border Validation
    
    /// Validates cross-border context is present
    /// RULE: Cross-border context obligatoire
    public func validateCrossBorderContext(
        transactionId: String,
        context: CrossBorderContext?
    ) throws {
        
        guard let context = context else {
            throw CrossBorderError.missingContext(transactionId: transactionId)
        }
        
        // Validate required fields
        guard !context.sourceCountry.isEmpty else {
            throw CrossBorderError.missingSourceCountry
        }
        
        guard !context.destinationCountry.isEmpty else {
            throw CrossBorderError.missingDestinationCountry
        }
        
        guard !context.sourceCurrency.isEmpty else {
            throw CrossBorderError.missingSourceCurrency
        }
        
        guard !context.destinationCurrency.isEmpty else {
            throw CrossBorderError.missingDestinationCurrency
        }
        
        // Check if cross-border
        if context.sourceCountry != context.destinationCountry {
            // Validate additional cross-border requirements
            try validateCrossBorderRequirements(context)
        }
        
        // Store context
        crossBorderTransactions[transactionId] = context
    }
    
    private func validateCrossBorderRequirements(_ context: CrossBorderContext) throws {
        
        // Regulatory compliance info required
        guard !context.regulatoryInfo.isEmpty else {
            throw CrossBorderError.missingRegulatoryInfo
        }
        
        // Exchange rate required if currencies differ
        if context.sourceCurrency != context.destinationCurrency {
            guard context.exchangeRate > 0 else {
                throw CrossBorderError.missingExchangeRate
            }
        }
        
        // Purpose of transfer required
        guard !context.purposeOfTransfer.isEmpty else {
            throw CrossBorderError.missingPurposeOfTransfer
        }
    }
    
    /// Checks if transaction is cross-border
    public func isCrossBorder(context: CrossBorderContext) -> Bool {
        context.sourceCountry != context.destinationCountry ||
        context.sourceCurrency != context.destinationCurrency
    }
    
    /// Gets cross-border context for transaction
    public func getContext(transactionId: String) -> CrossBorderContext? {
        crossBorderTransactions[transactionId]
    }
    
    // MARK: - Types
    
    public struct CrossBorderContext: Codable {
        public let sourceCountry: String
        public let destinationCountry: String
        public let sourceCurrency: String
        public let destinationCurrency: String
        public let exchangeRate: Double
        public let purposeOfTransfer: String
        public let regulatoryInfo: [String: String]
        public let timestamp: Date
        
        public init(
            sourceCountry: String,
            destinationCountry: String,
            sourceCurrency: String,
            destinationCurrency: String,
            exchangeRate: Double,
            purposeOfTransfer: String,
            regulatoryInfo: [String: String],
            timestamp: Date = Date()
        ) {
            self.sourceCountry = sourceCountry
            self.destinationCountry = destinationCountry
            self.sourceCurrency = sourceCurrency
            self.destinationCurrency = destinationCurrency
            self.exchangeRate = exchangeRate
            self.purposeOfTransfer = purposeOfTransfer
            self.regulatoryInfo = regulatoryInfo
            self.timestamp = timestamp
        }
    }
    
    public enum CrossBorderError: Error, LocalizedError {
        case missingContext(transactionId: String)
        case missingSourceCountry
        case missingDestinationCountry
        case missingSourceCurrency
        case missingDestinationCurrency
        case missingExchangeRate
        case missingPurposeOfTransfer
        case missingRegulatoryInfo
        
        public var errorDescription: String? {
            switch self {
            case .missingContext(let transactionId):
                return "Cross-border context missing for transaction \(transactionId)"
            case .missingSourceCountry:
                return "Source country is required"
            case .missingDestinationCountry:
                return "Destination country is required"
            case .missingSourceCurrency:
                return "Source currency is required"
            case .missingDestinationCurrency:
                return "Destination currency is required"
            case .missingExchangeRate:
                return "Exchange rate is required for cross-currency transactions"
            case .missingPurposeOfTransfer:
                return "Purpose of transfer is required for cross-border transactions"
            case .missingRegulatoryInfo:
                return "Regulatory information is required for cross-border transactions"
            }
        }
    }
}
