//
//  HTTPUserProfileDataSource.swift
//  FeatureChat
//

import Foundation
import WaanguCoreKit

/// Publishes the signed-in user's profile through
/// `PUT /identity/users/{id}` — the record contact sync reads back.
final class HTTPUserProfileDataSource: UserProfileRemoteDataSourceProtocol {
    private let apiClient: APIClientProtocol
    private let logger: any AppLoggerProtocol

    init(apiClient: APIClientProtocol, logger: any AppLoggerProtocol = AppLogger.shared) {
        self.apiClient = apiClient
        self.logger = logger
    }

    func updateProfile(_ profile: UserProfile) async throws {
        // `bio` goes out even when empty — clearing it is an edit the user can
        // make, and a dropped key would read as "leave it alone". `avatar` is
        // the opposite: the profile screen can only ever set a photo, so an
        // empty URL means "none picked", never "remove the one on file".
        let request = myProfileUpdateReq(
            username: profile.name,
            avatar: profile.avatarUrl.isEmpty ? nil : profile.avatarUrl,
            bio: profile.bio
        )

        do {
            // Any non-2xx surfaces as a thrown APIError, so returning at all is
            // the success signal the repository gates its local write on.
            let _: UpdateMyProfileResponse = try await apiClient.request(
                endpoint: ContactsEndpoints.updateMyProfile(request)
            )
        } catch {
            // The repository turns this into a short reason for the UI; the
            // full error only ever exists here.
            await logger.log(
                "Profile publish failed for \(profile.userId): \(error)",
                level: .error
            )
            throw error
        }
    }
}
