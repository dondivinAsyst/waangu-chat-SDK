//
//  FXDisclosureManager.swift
//  CoreKit
//
//  Manages FX disclosure for different currencies
//  RULE: FX disclosure obligatoire si devise différente

import Foundation
import WaanguCoreKit

public actor FXDisclosureManager {
    
    public static let shared = FXDisclosureManager()
    
    private var disclosures: [String: FXDisclosure] = [:]
    
    private init() {}
    
    // MARK: - FX Disclosure
    
    /// Validates FX disclosure is present when currencies differ
    /// RULE: FX disclosure obligatoire si devise différente
    public func validateFXDisclosure(
        transactionId: String,
        sourceCurrency: String,
        destinationCurrency: String,
        disclosure: FXDisclosure?
    ) throws {
        
        // Check if currencies differ
        guard sourceCurrency != destinationCurrency else {
            // Same currency, no disclosure needed
            return
        }
        
        // RULE: FX disclosure obligatoire si devise différente
        guard let disclosure = disclosure else {
            throw FXError.missingDisclosure(
                transactionId: transactionId,
                sourceCurrency: sourceCurrency,
                destinationCurrency: destinationCurrency
            )
        }
        
        // Validate disclosure completeness
        try validateDisclosureCompleteness(disclosure)
        
        // Store disclosure
        disclosures[transactionId] = disclosure
        
        // Audit
        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .security,
                metadata: [
                    "action": "fx_disclosure_validated",
                    "transaction_id": transactionId,
                    "source_currency": sourceCurrency,
                    "destination_currency": destinationCurrency,
                    "exchange_rate": String(disclosure.exchangeRate)
                ],
                severity: .info
            )
        }
    }
    
    private func validateDisclosureCompleteness(_ disclosure: FXDisclosure) throws {
        
        // Exchange rate must be positive
        guard disclosure.exchangeRate > 0 else {
            throw FXError.invalidExchangeRate(rate: disclosure.exchangeRate)
        }
        
        // Source amount must be positive
        guard disclosure.sourceAmount > 0 else {
            throw FXError.invalidAmount(amount: disclosure.sourceAmount)
        }
        
        // Destination amount must be positive
        guard disclosure.destinationAmount > 0 else {
            throw FXError.invalidAmount(amount: disclosure.destinationAmount)
        }
        
        // Fee must be non-negative
        guard disclosure.feeAmount >= 0 else {
            throw FXError.invalidFee(fee: disclosure.feeAmount)
        }
        
        // Rate source must be specified
        guard !disclosure.rateSource.isEmpty else {
            throw FXError.missingRateSource
        }
        
        // User must have acknowledged
        guard disclosure.userAcknowledged else {
            throw FXError.userNotAcknowledged
        }
    }
    
    /// Creates FX disclosure
    public func createDisclosure(
        sourceCurrency: String,
        destinationCurrency: String,
        sourceAmount: Double,
        destinationAmount: Double,
        exchangeRate: Double,
        feeAmount: Double,
        feeCurrency: String,
        rateSource: String,
        rateTimestamp: Date
    ) -> FXDisclosure {
        
        FXDisclosure(
            sourceCurrency: sourceCurrency,
            destinationCurrency: destinationCurrency,
            sourceAmount: sourceAmount,
            destinationAmount: destinationAmount,
            exchangeRate: exchangeRate,
            feeAmount: feeAmount,
            feeCurrency: feeCurrency,
            rateSource: rateSource,
            rateTimestamp: rateTimestamp,
            userAcknowledged: false,
            acknowledgedAt: nil
        )
    }
    
    /// Marks disclosure as acknowledged by user
    public func acknowledgeDisclosure(transactionId: String) throws {
        guard var disclosure = disclosures[transactionId] else {
            throw FXError.disclosureNotFound(transactionId: transactionId)
        }
        
        disclosure.userAcknowledged = true
        disclosure.acknowledgedAt = Date()
        disclosures[transactionId] = disclosure
    }
    
    /// Gets disclosure for transaction
    public func getDisclosure(transactionId: String) -> FXDisclosure? {
        disclosures[transactionId]
    }
    
    // MARK: - Types
    
    public struct FXDisclosure: Codable {
        public let sourceCurrency: String
        public let destinationCurrency: String
        public let sourceAmount: Double
        public let destinationAmount: Double
        public let exchangeRate: Double
        public let feeAmount: Double
        public let feeCurrency: String
        public let rateSource: String
        public let rateTimestamp: Date
        public var userAcknowledged: Bool
        public var acknowledgedAt: Date?
        
        public init(
            sourceCurrency: String,
            destinationCurrency: String,
            sourceAmount: Double,
            destinationAmount: Double,
            exchangeRate: Double,
            feeAmount: Double,
            feeCurrency: String,
            rateSource: String,
            rateTimestamp: Date,
            userAcknowledged: Bool,
            acknowledgedAt: Date?
        ) {
            self.sourceCurrency = sourceCurrency
            self.destinationCurrency = destinationCurrency
            self.sourceAmount = sourceAmount
            self.destinationAmount = destinationAmount
            self.exchangeRate = exchangeRate
            self.feeAmount = feeAmount
            self.feeCurrency = feeCurrency
            self.rateSource = rateSource
            self.rateTimestamp = rateTimestamp
            self.userAcknowledged = userAcknowledged
            self.acknowledgedAt = acknowledgedAt
        }
    }
    
    public enum FXError: Error, LocalizedError {
        case missingDisclosure(transactionId: String, sourceCurrency: String, destinationCurrency: String)
        case invalidExchangeRate(rate: Double)
        case invalidAmount(amount: Double)
        case invalidFee(fee: Double)
        case missingRateSource
        case userNotAcknowledged
        case disclosureNotFound(transactionId: String)
        
        public var errorDescription: String? {
            switch self {
            case .missingDisclosure(let transactionId, let source, let destination):
                return "FX disclosure required for transaction \(transactionId) (\(source) → \(destination))"
            case .invalidExchangeRate(let rate):
                return "Invalid exchange rate: \(rate)"
            case .invalidAmount(let amount):
                return "Invalid amount: \(amount)"
            case .invalidFee(let fee):
                return "Invalid fee: \(fee)"
            case .missingRateSource:
                return "Rate source must be specified"
            case .userNotAcknowledged:
                return "User must acknowledge FX disclosure"
            case .disclosureNotFound(let transactionId):
                return "FX disclosure not found for transaction \(transactionId)"
            }
        }
    }
}
