//
//  ShareContentProcessor.swift
//  FeatureChat
//
//  Created by Kiro AI

import Foundation
import WaanguCoreKit

/// Processes shared content from Share Extension
class ShareContentProcessor: ShareContentProcessorProtocol {
    
    private let contactsUseCases: ContactsUseCasesProtocol
    
    init(contactsUseCases: ContactsUseCasesProtocol) {
        self.contactsUseCases = contactsUseCases
    }
    
    func processSharedContent(from url: URL) async throws {
        debugLog("[ShareContentProcessor] Processing shared content (scheme: \(url.scheme ?? "nil"))")
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            debugLog("[ShareContentProcessor] Failed to parse URL components")
            return
        }
        
        // Extract shared content from URL parameters
        let content = extractContentFromQuery(queryItems)
        let destination = extractDestinationFromQuery(queryItems)
        let contactIds = extractContactIdsFromQuery(queryItems)
        
        debugLog("[ShareContentProcessor] Content type: \(content.type.rawValue)")
        debugLog("[ShareContentProcessor] Destination: \(destination?.rawValue ?? "none")")
        debugLog("[ShareContentProcessor] Contact IDs: \(contactIds)")
        
        // Process based on destination
        switch destination {
        case .contacts:
            if !contactIds.isEmpty {
                try await sendContentToContacts(content: content, contactIds: contactIds)
            }
        case .story:
            try await postContentToStory(content: content)
        case .none:
            debugLog("[ShareContentProcessor] No destination specified")
        }
    }
    
    // MARK: - Private Methods
    
    private func extractContentFromQuery(_ queryItems: [URLQueryItem]) -> ProcessableShareContent {
        var text: String?
        var imageData: Data?
        var videoURL: URL?
        var fileURL: URL?
        var type: ShareContentType = .text
        
        for item in queryItems {
            switch item.name {
            case "text":
                text = item.value
                type = .text
            case "imageFile":
                // Image files are handled via App Groups - the filename is passed
                // The main app will retrieve the actual image data using SharedDataManager
                if let filename = item.value {
                    // Store the filename for later retrieval by the main app
                    debugLog("[ShareContentProcessor] Image file: \(filename)")
                    type = .image
                }
            case "video":
                if let urlString = item.value {
                    videoURL = URL(string: urlString)
                    type = .video
                }
            case "file":
                if let urlString = item.value {
                    fileURL = URL(string: urlString)
                    type = .file
                }
            case "type":
                if let typeString = item.value {
                    type = ShareContentType(rawValue: typeString) ?? .text
                }
            default:
                break
            }
        }
        
        return ProcessableShareContent(
            text: text,
            imageData: imageData,
            videoURL: videoURL,
            fileURL: fileURL,
            type: type
        )
    }
    
    private func extractDestinationFromQuery(_ queryItems: [URLQueryItem]) -> ProcessableShareContent.ShareDestinationType? {
        for item in queryItems {
            if item.name == "destination", let value = item.value {
                return ProcessableShareContent.ShareDestinationType(rawValue: value)
            }
        }
        return nil
    }
    
    private func extractContactIdsFromQuery(_ queryItems: [URLQueryItem]) -> [String] {
        for item in queryItems {
            if item.name == "contactIds", let value = item.value {
                return value.split(separator: ",").map(String.init)
            }
        }
        return []
    }
    
    private func sendContentToContacts(content: ProcessableShareContent, contactIds: [String]) async throws {
        debugLog("[ShareContentProcessor] Sending content to \(contactIds.count) contacts")
        
        // Here we would integrate with the existing message sending infrastructure
        // For now, we'll create a placeholder that can be completed with actual message sending logic
        
        // TODO: Integrate with ChatRoomViewModel.sendMediaAndTextMessage or similar
        // This would require:
        // 1. Converting shared content to MessageContent format
        // 2. Finding or creating discussions with the selected contacts
        // 3. Sending the message through the existing message flow
        
        for contactId in contactIds {
            debugLog("[ShareContentProcessor] Would send to contact: \(contactId)")
            
            // Placeholder for actual message sending
            // let messageContent = convertToMessageContent(content)
            // let discussion = try await findOrCreateDiscussion(with: contactId)
            // try await sendMessage(messageContent, to: discussion)
        }
    }
    
    private func postContentToStory(content: ProcessableShareContent) async throws {
        debugLog("[ShareContentProcessor] Posting content to story")
        
        // TODO: Integrate with existing story posting functionality
        // This would require integrating with the Stories feature
        
        debugLog("[ShareContentProcessor] Would post to story: \(content.type.rawValue)")
    }
}