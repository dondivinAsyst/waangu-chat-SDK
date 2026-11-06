//
//  ChatAuthInitViewModel.swift
//  FeatureChat
//
//  Created by Don divin on 5/20/26.
//

import Foundation
import Combine
import WaanguCoreKit

@MainActor
public final class ChatAuthInitViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var authState: AuthState = .initializing
    /// Pourquoi le démarrage a échoué — l'écran en tire son icône et son texte.
    /// C'était une phrase déjà rédigée, en français quelle que soit la langue.
    @Published public private(set) var failure: ChatStartFailure?
    /// Nouvel essai en cours depuis l'écran d'échec : on reste sur cet écran,
    /// le bouton tourne, au lieu de repasser par « Initialisation ».
    @Published public private(set) var isRetrying = false
    
    // MARK: - Dependencies
    private let authUseCases: AuthUseCasesProtocol
    private let currentSessionUseCase: CurrentSessionUseCaseProtocol
    private let eventBus: any EventBusProtocol
    private let discussionRepository: DiscussionRepositoryProtocol
    
    // MARK: - Init
    public init(
        authUseCases: AuthUseCasesProtocol,
        currentSessionUseCase: CurrentSessionUseCaseProtocol,
        eventBus: any EventBusProtocol,
        discussionRepository: DiscussionRepositoryProtocol
    ) {
        self.authUseCases = authUseCases
        self.currentSessionUseCase = currentSessionUseCase
        self.eventBus = eventBus
        self.discussionRepository = discussionRepository
    }
    
    // MARK: - Public Methods
    
    /// Check authentication status on app launch
    public func checkAuthenticationStatus() async {
        debugLog("session to check authentication session: started")
        authState = .initializing
        failure = nil
//      await authenticate()
        do {
            if let session = try await currentSessionUseCase.loadCurrentSession() {
                if try await currentSessionUseCase.shouldReauthenticate() {
                    await authenticate()
                } else {
                    
                    authState = .authenticated(session)
                    performFullSync()
                    await eventBus.publish(UserChatDidLoginEvent(userId: session.userId))
                }
             
            } else {
               
                await authenticate()
            }
        } catch {
            debugLog("❌ Failed to check authentication status: \(error)")
            await authenticate()
        }
    }
    
    public func authenticate() async {
        authState = .initializing
        failure = nil
        
        // Add a small delay for better UX (shows animation)
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        await attemptAuthentication()
    }
    
    public func retry() async {
        guard !isRetrying else { return }
        isRetrying = true
        defer { isRetrying = false }
        await attemptAuthentication()
    }
    
    // MARK: - Private Methods
    
    private func attemptAuthentication() async {
        // Aucune réponse du service d'authentification : réseau ou serveur,
        // l'utilisateur ne peut agir que sur sa connexion.
        guard let authInfo = await authUseCases.authenticate.execute() else {
            fail(.network)
            return
        }
        // Réponse reçue, mais la session n'a pas pu être enregistrée.
        guard let session = await persistAuthenticatedSession(authInfo: authInfo) else {
            fail(.session)
            return
        }
        failure = nil
        authState = .authenticated(session)
        await eventBus.publish(UserChatDidLoginEvent(userId: authInfo.userId))
    }
    
    private func fail(_ reason: ChatStartFailure) {
        failure = reason
        authState = .failed
    }
    
    private func persistAuthenticatedSession(authInfo: AuthSessionInfo) async -> CurrentSession? {
        var retryCount = 0
        let maxRetries = 3
        
        while retryCount < maxRetries {
            do {
                let session = try await currentSessionUseCase.saveAuthenticatedSession(authInfo)
                
                debugLog("✅ Session persisted successfully")
                return session
            } catch {
                let errorDescription = "\(error)"
                
                if errorDescription.contains("no such table") && retryCount < maxRetries - 1 {
                    retryCount += 1
                    debugLog("⚠️ Database not ready yet (attempt \(retryCount)/\(maxRetries)), retrying in 500ms...")
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    continue
                } else {
                    debugLog("❌ Failed to persist authenticated session: \(error)")
                    return nil
                }
            }
        }
        
        debugLog("❌ Failed to persist authenticated session after \(maxRetries) attempts")
        return nil
    }
    
    private func performFullSync() {
        Task {
            do {
                debugLog("🌎🔄 Starting full conversation and message sync...")
                try await discussionRepository.performFullSync(limit: 50)
                debugLog("🌎✅ Full sync completed successfully")
                // After the sync, not before: the server rows have to be here
                // before the local ones can be folded into them.
                await discussionRepository.deduplicateConversationsIfNeeded()
            } catch {
                debugLog("🌎❌ Full sync failed: \(error)")
                // ✅ Record sync failure
                SyncHealthMonitor.shared.recordSyncFailure(topic: .conversations, error: error)
                // Don't block authentication on sync failure
            }
        }
    }
}

// MARK: - Start Failure
public enum ChatStartFailure: Equatable, Sendable {
    /// Le service d'authentification n'a pas répondu.
    case network
    /// Il a répondu, mais la session locale n'a pas pu être créée.
    case session
}

// MARK: - Auth State
public enum AuthState: Equatable {
    case initializing
    case authenticated(CurrentSession)
    case failed
    
    public static func == (lhs: AuthState, rhs: AuthState) -> Bool {
        switch (lhs, rhs) {
        case (.initializing, .initializing):
            return true
        case (.authenticated, .authenticated):
            return true
        case (.failed, .failed):
            return true
        default:
            return false
        }
    }
}
