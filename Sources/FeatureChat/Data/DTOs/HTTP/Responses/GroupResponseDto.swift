//
//  GroupResponseDto.swift
//  AppModules
//
//  Created by Don divin on 5/28/26.
//


import Foundation

/// Wrapper for API responses that contain data, message, and status
public struct GroupAPIResponse: Codable {
    let message: String?
    let status: Int?
    let data: GroupResponseDto
}

/// Groupe (équipe / canal), aligné sur la persistance contact_groups
public struct GroupResponseDto: Codable {
    
    /// Identifiant du groupe
    let id: String
    
    /// Propriétaire du groupe (ID utilisateur)
    let ownerId: String
    
    /// Tenant Keycloak / isolation
    let tenantId: String?
    
    /// Nom du groupe
    let name: String
    
    /// Description
    let description: String?
    
    /// Image (URL ou clé), distincte de l’icône
    let image: String?
    
    /// Icône (URL ou clé)
    let icon: String?
    
    /// Couleur d’affichage
    let color: String?
    
    /// Groupe par défaut du propriétaire
    let isDefault: Bool?
    
    /// Ordre d’affichage
    let sortOrder: Int?
    
    /// Nombre de membres
    let memberCount: Int?
    
    /// Type d'équipe
    let teamType: String?
    
    /// Mode de routage
    let routingType: String?
    
    /// ID horaires métier
    let businessHoursId: String?
    
    /// Assignation automatique des conversations
    let autoAssignEnabled: Bool?
    
    /// Routage lorsque l’équipe est hors ligne
    let offlineRoutingEnabled: Bool?
    
    /// Cible routage hors ligne (groupe ou agent)
    let offlineRoutingTo: String?
    
    /// Plafond d'assignations par agent
    let maxAssignPerAgent: Int?
    
    /// Actif
    let isActive: Bool?
    
    /// Conversations actives
    let activeConversationCount: Int?
    
    /// Communauté rattachée
    let communityId: String?
    
    /// Groupe d’annonces communauté
    let isAnnouncementGroup: Bool?
    
    /// Métadonnées libres
    let metadata: String?
    
    /// Date de création
    let createdAt: Date?
    
    /// Date de mise à jour
    let updatedAt: Date?
    
    /// Membres du groupe
//    let members: [GroupMemberEntryDto]?
    public init(id: String, ownerId: String, tenantId: String?, name: String, description: String?, image: String?, icon: String?, color: String?, isDefault: Bool?, sortOrder: Int?, memberCount: Int?, teamType: String?, routingType: String?, businessHoursId: String?, autoAssignEnabled: Bool?, offlineRoutingEnabled: Bool?, offlineRoutingTo: String?, maxAssignPerAgent: Int?, isActive: Bool?, activeConversationCount: Int?, communityId: String?, isAnnouncementGroup: Bool?, metadata: String?, createdAt: Date?, updatedAt: Date?) {
        self.id = id
        self.ownerId = ownerId
        self.tenantId = tenantId
        self.name = name
        self.description = description
        self.image = image
        self.icon = icon
        self.color = color
        self.isDefault = isDefault
        self.sortOrder = sortOrder
        self.memberCount = memberCount
        self.teamType = teamType
        self.routingType = routingType
        self.businessHoursId = businessHoursId
        self.autoAssignEnabled = autoAssignEnabled
        self.offlineRoutingEnabled = offlineRoutingEnabled
        self.offlineRoutingTo = offlineRoutingTo
        self.maxAssignPerAgent = maxAssignPerAgent
        self.isActive = isActive
        self.activeConversationCount = activeConversationCount
        self.communityId = communityId
        self.isAnnouncementGroup = isAnnouncementGroup
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct InviteResponseDTO: Codable {
    let message: String
    let status: Int
    let data: InviteDataDTO
//    let metadata: MetadataDTO
}

public struct InviteDataDTO: Codable {
    let groupId: String
    let inviteCode: String
    let inviteLink: String
    let expiresAt: Date?
    let remainingUses: Int?
}

public struct MetadataDTO: Codable {
    let page: Int
    let limit: Int
    let totalPages: Int
    let totalElements: Int
}
