//
//  ShareContentProcessorProtocol.swift
//  CoreKit
//
//  Created by Kiro AI

import Foundation

/// Protocol for processing shared content from Share Extension
public protocol ShareContentProcessorProtocol {
    /// Process shared content from deep link URL
    func processSharedContent(from url: URL) async throws
}

/// Shared content types
public enum ShareContentType: String, Codable, CaseIterable {
    case text
    case image
    case video
    case file
    case url
}

/// Shared content model
public struct ProcessableShareContent: Codable {
    public let text: String?
    public let imageData: Data?
    public let videoURL: URL?
    public let fileURL: URL?
    public let type: ShareContentType
    public let destinationType: ShareDestinationType?
    public let contactIds: [String]?
    
    public enum ShareDestinationType: String, Codable {
        case contacts
        case story
    }
    
    public init(
        text: String? = nil,
        imageData: Data? = nil,
        videoURL: URL? = nil,
        fileURL: URL? = nil,
        type: ShareContentType,
        destinationType: ShareDestinationType? = nil,
        contactIds: [String]? = nil
    ) {
        self.text = text
        self.imageData = imageData
        self.videoURL = videoURL
        self.fileURL = fileURL
        self.type = type
        self.destinationType = destinationType
        self.contactIds = contactIds
    }
}