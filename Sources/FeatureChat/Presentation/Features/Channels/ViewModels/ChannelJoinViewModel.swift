//
//  ChannelJoinViewModel.swift
//  FeatureChat
//
//  Handles channel preview and joining via invite code for link recipients.
//

import Foundation
import Combine

@MainActor
final class ChannelJoinViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var channel: Channel?
    @Published var isLoadingChannel = false
    @Published var isJoining = false
    @Published var errorMessage: String?
    @Published var joinSuccessful = false
    @Published var wasAlreadySubscribed = false
    
    // MARK: - Properties
    
    let inviteCode: String
    private let channelUseCases: ChannelUseCasesProtocol
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Computed Properties
    
    var canJoin: Bool {
        channel != nil && !isJoining && !joinSuccessful
    }
    
    var joinButtonText: String {
        if wasAlreadySubscribed {
            return "Already Joined"
        } else if joinSuccessful {
            return "Joined"
        } else if isJoining {
            return "Joining..."
        } else {
            return "Join Channel"
        }
    }
    
    // MARK: - Initialization
    
    init(inviteCode: String, channelUseCases: ChannelUseCasesProtocol) {
        self.inviteCode = inviteCode
        self.channelUseCases = channelUseCases
    }
    
    // MARK: - Actions
    
    /// Validates the invite code and fetches channel details for preview.
    /// This does NOT subscribe the user - it only shows what they would join.
    func loadChannelPreview() {
        Task {
            isLoadingChannel = true
            errorMessage = nil
            
            do {
                // Join by code returns the channel and subscription status
                // If already subscribed, this is idempotent
                let (fetchedChannel, alreadySubscribed) = try await channelUseCases.joinByCode.execute(
                    inviteCode: inviteCode
                )
                
                self.channel = fetchedChannel
                self.wasAlreadySubscribed = alreadySubscribed
                
                // If they were already subscribed, mark as successful immediately
                if alreadySubscribed {
                    self.joinSuccessful = true
                }
                
            } catch {
                self.errorMessage = mapError(error)
            }
            
            isLoadingChannel = false
        }
    }
    
    /// Joins the channel using the invite code.
    /// The backend handles the subscription via the joinByCode endpoint.
    func joinChannel() {
        guard canJoin else { return }
        
        Task {
            isJoining = true
            errorMessage = nil
            
            do {
                let (fetchedChannel, alreadySubscribed) = try await channelUseCases.joinByCode.execute(
                    inviteCode: inviteCode
                )
                
                self.channel = fetchedChannel
                self.wasAlreadySubscribed = alreadySubscribed
                self.joinSuccessful = true
                
            } catch {
                self.errorMessage = mapError(error)
            }
            
            isJoining = false
        }
    }
    
    // MARK: - Private Helpers
    
    private func mapError(_ error: Error) -> String {
        if let channelError = error as? ChannelError {
            switch channelError {
            case .notFound:
                return ChatErrorStrings.channelInviteInvalid
            case .banned:
                return ChatErrorStrings.channelJoinBanned
            case .forbidden:
                return ChatErrorStrings.channelJoinForbidden
            case .tenantMismatch:
                return ChatErrorStrings.channelUnavailableInRegion
            case .server(_, let message):
                return message ?? ChatErrorStrings.channelJoinFailed
            case .missingConversation:
                return ChatErrorStrings.channelUnavailable
            }
        }

        return ChatErrorStrings.channelJoinFailedRetry
    }
}
