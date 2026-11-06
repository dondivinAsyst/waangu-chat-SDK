//
//  CurrentUserUseCaseProtocol.swift
//  FeatureChat
//
//  Created by Architecture Team on 5/28/26.
//

import Foundation

public protocol CurrentUserUseCaseProtocol {
    /// Load current user from storage
    func loadCurrentUser() async throws -> CurrentUser?
    
    /// Logout and clear user session
    func logout() async throws
    
    /// Check if user should re-authenticate
    func shouldReauthenticate() async throws -> Bool
}
