//
//  SecurityKit.swift
//  SecurityKit
//
//  Security and compliance components
//
//  This module provides enterprise-grade security and compliance features
//  for the Waangu application, including message validation, payment security,
//  AI safety, fraud detection, and regulatory compliance.

import Foundation
import WaanguCoreKit
import WaanguStorageKit

/// SecurityKit version information
public struct SecurityKit {
    public static let version = "1.0.0"
}

// MARK: - Crypto Exports
// Re-export all crypto components so users can import SecurityKit and get complete crypto functionality
// This consolidates all WaanguCrypto functionality into SecurityKit

// MARK: - Field Encryption
public typealias SecurityFieldEncryptionService = FieldEncryptionService

// MARK: - E2EE Queue Management  
public typealias SecurityPendingE2EEQueue = PendingE2EEQueue

// MARK: - E2EE Core Services
public typealias SecurityE2EEService = E2EEService
public typealias SecurityCryptoService = CryptoService
public typealias SecurityConversationCryptoService = ConversationCryptoService

// MARK: - E2EE Key Management
public typealias SecurityE2EEKeyStore = E2EEKeyStore

// MARK: - E2EE Cryptographic Protocols
public typealias SecurityDoubleRatchet = DoubleRatchet
public typealias SecurityX3DHService = X3DHService

// MARK: - E2EE Data Models
// These models are now defined in CoreKit to avoid protocol/implementation mismatches
// Re-export them for easy access
public typealias SecuritySessionState = WaanguCoreKit.SessionState
public typealias SecurityMessageHeader = WaanguCoreKit.MessageHeader
public typealias SecurityEncryptedEnvelope = WaanguCoreKit.EncryptedEnvelope
public typealias SecuritySessionSetupPayload = WaanguCoreKit.SessionSetupPayload
public typealias SecurityPublicKeyBundle = WaanguCoreKit.PublicKeyBundle
public typealias SecurityE2EEError = WaanguCoreKit.E2EEError
