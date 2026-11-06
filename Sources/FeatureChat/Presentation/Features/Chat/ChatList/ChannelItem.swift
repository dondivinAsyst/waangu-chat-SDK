//
//  ChannelItem.swift
//  WhatsAppClone
//
//  Created by Muharrem Efe Çayırbahçe on 14.01.2025.
//

import Foundation


public struct ChannelItem: Identifiable, Hashable {
    public  var id: String
    var name: String?
    private var lastMessage: String
    var creationDate: Date
    var lastMessageTimestamp: Date
    var membersCount: Int
    var adminUids: [String]
    var memberUids: [String]
    var members: [UserItem]
    private var thumbnailUrl: String?
    let createdBy: String
    let lastMessageType: MessageType
    
    var isGroupChat: Bool {
        return membersCount > 2
    }
    
    var coverImageUrl: String? {
        if let thumbnailUrl = thumbnailUrl {
            return thumbnailUrl
        }
        
        if isGroupChat == false {
            return membersExcludingMe.first?.profileImageURL
        }
        
        return nil
    }
    
    var membersExcludingMe: [UserItem] {
//        guard let currentUid = Auth.auth().currentUser?.uid else { return [] }
        return members.filter { $0.uid != "currentUid" }
    }
    
    var title: String {
        if let name = name {
            return name
        }
        
        if isGroupChat {
            return groupMemberNames
        } else {
            return membersExcludingMe.first?.username ?? "Unknown User"
        }
    }
    
    private var groupMemberNames: String {
        let membersCount = membersCount - 1
        let fullNames: [String] = membersExcludingMe.map { $0.username }
        
        if membersCount == 2 {
            return fullNames.joined(separator: " and ")
        } else if membersCount > 2 {
            let remainingCount = membersCount - 2
            return fullNames.prefix(2).joined(separator: ", ") + " and \(remainingCount) others"
        }
        
        return "Unknown"
    }
    
    var isCreatedByMe: Bool {
        return createdBy == "Auth.auth().currentUser?.uid" ?? ""
    }
    
    var creatorName: String {
        return members.first { $0.uid == createdBy }?.username ?? "Unknown User"
    }
    
    var allMembersFetched: Bool {
        return members.count == membersCount
    }
    
    var previewMessage: String {
        switch lastMessageType {
            
        case .admin:
            return "New Channel Created"
        case .text:
            return lastMessage
        case .photo:
            return "Photo"
        case .video:
            return "Video"
        case .audio:
            return "Audio"
        }
    }
    
     init(
        id: String,
        name: String? = nil,
        lastMessage: String,
        creationDate: Date,
        lastMessageTimestamp: Date,
        membersCount: Int,
        adminUids: [String],
        memberUids: [String],
        members: [UserItem],
        thumbnailUrl: String? = nil,
        createdBy: String,
        lastMessageType: MessageType
    ) {
        self.id = id
        self.name = name
        self.lastMessage = lastMessage
        self.creationDate = creationDate
        self.lastMessageTimestamp = lastMessageTimestamp
        self.membersCount = membersCount
        self.adminUids = adminUids
        self.memberUids = memberUids
        self.members = members
        self.thumbnailUrl = thumbnailUrl
        self.createdBy = createdBy
        self.lastMessageType = lastMessageType
    }

    public static let placeholder = ChannelItem(
        id: "1",
        lastMessage: "Hello World!",
        creationDate: Date(),
        lastMessageTimestamp: Date(),
        membersCount: 2,
        adminUids: [],
        memberUids: [],
        members: [],
        createdBy: "",
        lastMessageType: .text
    )
}
