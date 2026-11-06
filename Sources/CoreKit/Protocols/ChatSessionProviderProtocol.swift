//
//  ChatSessionProviderProtocol.swift
//  CoreKit
//
//  Provides chat session id for network middleware injection.
//

import Foundation

public protocol ChatSessionProviderProtocol: Sendable {
    func getChatSessionId() async throws -> String?
}
