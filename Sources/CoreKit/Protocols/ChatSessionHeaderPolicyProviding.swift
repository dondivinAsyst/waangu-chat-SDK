//
//  ChatSessionHeaderPolicyProviding.swift
//  CoreKit
//

import Foundation

/// Endpoint-level policy for chat session header injection.
public protocol ChatSessionHeaderPolicyProviding {
    /// Return false for endpoints that must not receive `x-chat-session`.
    var requiresChatSessionHeader: Bool { get }
}
