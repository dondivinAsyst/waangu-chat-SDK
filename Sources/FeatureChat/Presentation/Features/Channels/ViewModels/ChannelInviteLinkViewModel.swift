//
//  ChannelInviteLinkViewModel.swift
//  FeatureChat
//
//  Manages channel invite link generation, viewing, and revocation for channel owners.
//

import Foundation
import Combine
import UIKit

@MainActor
final class ChannelInviteLinkViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var inviteLink: ChannelInviteLink?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showShareSheet = false
    @Published var showRevokeConfirmation = false
    
    // MARK: - Properties
    
    let channel: Channel
    private let channelUseCases: ChannelUseCasesProtocol
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Computed Properties
    
    var hasActiveLink: Bool {
        guard let link = inviteLink else { return false }
        return link.isActive && !link.isExpired && !link.hasReachedMaxUses
    }
    
    var linkStatusText: String {
        guard let link = inviteLink else { return "No active link" }
        
        if link.isExpired {
            return "Expired"
        } else if link.hasReachedMaxUses {
            return "Max uses reached"
        } else if !link.isActive {
            return "Inactive"
        } else {
            return "Active"
        }
    }
    
    var linkUsageText: String? {
        guard let link = inviteLink else { return nil }
        
        if let maxUses = link.maxUses {
            return "\(link.currentUses) / \(maxUses) uses"
        } else {
            return "\(link.currentUses) uses"
        }
    }
    
    var linkExpirationText: String? {
        guard let link = inviteLink, let expiresAt = link.expiresAt else { return nil }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Expires \(formatter.localizedString(for: expiresAt, relativeTo: Date()))"
    }
    
    // MARK: - Initialization
    
    init(channel: Channel, channelUseCases: ChannelUseCasesProtocol) {
        self.channel = channel
        self.channelUseCases = channelUseCases
    }
    
    // MARK: - Actions
    
    func loadInviteLink() {
        Task {
            isLoading = true
            errorMessage = nil
            
            do {
                let link = try await channelUseCases.getInviteLink.execute(channelId: channel.id)
                self.inviteLink = link
            } catch {
                // If no link exists, that's fine - user can generate one
                if case ChannelError.notFound = error {
                    self.inviteLink = nil
                } else {
                    self.errorMessage = ChatErrorStrings.channelInviteLinkLoadFailed
                }
            }
            
            isLoading = false
        }
    }
    
    func generateInviteLink(expiresIn: Int? = nil, maxUses: Int? = nil) {
        Task {
            isLoading = true
            errorMessage = nil
            
            do {
                let link = try await channelUseCases.generateInviteLink.execute(
                    channelId: channel.id,
                    expiresIn: expiresIn,
                    maxUses: maxUses
                )
                self.inviteLink = link
            } catch {
                self.errorMessage = ChatErrorStrings.channelInviteLinkGenerateFailed
            }
            
            isLoading = false
        }
    }
    
    func regenerateInviteLink() {
        // Regenerating is the same as generating - backend handles overwrites
        generateInviteLink()
    }
    
    func shareInviteLink() {
        guard hasActiveLink else { return }
        showShareSheet = true
    }
    
    func copyInviteLinkToClipboard() {
        guard let link = inviteLink else { return }
        
        #if os(iOS)
        UIPasteboard.general.string = link.inviteUrl
        #endif
        
        // Could show a toast notification here
    }
    
    func revokeInviteLink() {
        Task {
            isLoading = true
            errorMessage = nil
            showRevokeConfirmation = false
            
            do {
                try await channelUseCases.revokeInviteLink.execute(channelId: channel.id)
                self.inviteLink = nil
            } catch {
                self.errorMessage = ChatErrorStrings.channelInviteLinkRevokeFailed
            }
            
            isLoading = false
        }
    }
    
    func confirmRevoke() {
        showRevokeConfirmation = true
    }
}
