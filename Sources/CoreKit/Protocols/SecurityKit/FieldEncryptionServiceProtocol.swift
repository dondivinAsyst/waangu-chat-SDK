//
//  FieldEncryptionServiceProtocol.swift
//  CoreKit
//
//  Protocol abstraction for field-level encryption service

import Foundation

/// Protocol for field-level data encryption/decryption
public protocol FieldEncryptionServiceProtocol: Sendable {
    
    /// Encrypt a string value
    func encrypt(_ value: String) -> String
    
    /// Decrypt a string value
    func decrypt(_ value: String) -> String
    
    /// Encrypt an optional string value
    func encryptOptional(_ value: String?) -> String?
    
    /// Decrypt an optional string value
    func decryptOptional(_ value: String?) -> String?
    
    /// Encrypt data
    func encryptData(_ data: Data) -> Data
    
    /// Decrypt data
    func decryptData(_ data: Data) -> Data
}