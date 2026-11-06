import Foundation

struct BlockContactResponse: Codable {
    let message: String
    let status: Int
    let data: ContactData
}

struct ContactData: Codable {
    let id: String
    let ownerId: String
    let tenantId: String
    let organisationId: String
    let contactName: String
    let codeCountry: String?
    let alias: String?
    let description: String?
    let isFavorite: Bool
    let isBlocked: Bool
    let whoCanSeeLastSeen: Bool
    let whoCanSeeImOnline: Bool
    let whoCanAddmeTogroup: Bool
    let blockedAt: String?
    let blockedReason: String?
    let metadata: String?
    let createdAt: String
    let updatedAt: String
    let role: String?
    let userName: String
    let email: String
    let firstName: String
    let lastName: String
    let fullName: String
    let image: String?
    let typeUser: String
    let status: String
    let bio: String?
    let lastSeen: String?
    let country: String?
    let phone: String?
    let userId: String
    let contactphone: String
    let additionalInfos: AdditionalInfos?
}

struct AdditionalInfos: Codable {
    let relationship: String?
    let alternativePhone: String?
}
