//
//  CurrentSessionUseCaseProtocol.swift
//  FeatureChat
//
//  Created by Architecture Team on 6/4/26.
//

import Foundation

public protocol CurrentSessionUseCaseProtocol {
    func saveAuthenticatedSession(_ authInfo: AuthSessionInfo) async throws -> CurrentSession
    func loadCurrentSession() async throws -> CurrentSession?
    func clearSession() async throws
    func shouldReauthenticate() async throws -> Bool
}
