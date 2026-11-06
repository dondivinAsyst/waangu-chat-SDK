//
//  CurrentSession.swift
//  FeatureChat
//
//  Created by Architecture Team on 6/4/26.
//

import Foundation

/// Authentication session source-of-truth for FeatureChat.
/// Keep this model independent from `CurrentUser`:
/// - Do not import or reference `CurrentUser` here.
/// - Persist and clear session data through `CurrentSession*` layers only.
/// - Mapping from auth API payloads should terminate in this model first.
public struct CurrentSession: Equatable, Sendable {
    public let redirectUrl: String
    public let sessionId: String
    public let appId: String
    public let userId: String
    public let email: String
    public let name: String
    public let tenantId: String
    public let organisationId: String
    public let country: String
    public let phone: String
    public let expiresAt: Date?
    public let lastAuthenticatedAt: Date

    public init(
        redirectUrl: String,
        sessionId: String,
        appId: String,
        userId: String,
        email: String,
        name: String,
        tenantId: String,
        organisationId: String,
        country: String,
        phone: String,
        expiresAt: Date?,
        lastAuthenticatedAt: Date = Date()
    ) {
        self.redirectUrl = redirectUrl
        self.sessionId = sessionId
        self.appId = appId
        self.userId = userId
        self.email = email
        self.name = name
        self.tenantId = tenantId
        self.organisationId = organisationId
        self.country = country
        self.phone = phone
        self.expiresAt = expiresAt
        self.lastAuthenticatedAt = lastAuthenticatedAt
    }
}

public extension CurrentSession {

}


