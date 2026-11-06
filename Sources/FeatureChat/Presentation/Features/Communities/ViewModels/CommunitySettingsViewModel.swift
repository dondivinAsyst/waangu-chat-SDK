//
//  CommunitySettingsViewModel.swift
//  FeatureChat
//

import Foundation
import WaanguCoreKit

/// Holds a community's permissions and saves each change as it is made.
///
/// Saved on change rather than behind a Save button: there are two switches, and
/// a screen with two switches and a commit step is a screen people leave without
/// committing.
@MainActor
public final class CommunitySettingsViewModel: ObservableObject {

    @Published private(set) var settings = CommunitySettings()
    @Published var errorMessage: String?

    private let communityId: String
    private let useCases: CommunityUseCasesProtocol
    let translationService: (any TranslationServiceProtocol)?

    public init(
        communityId: String,
        useCases: CommunityUseCasesProtocol,
        translationService: (any TranslationServiceProtocol)?
    ) {
        self.communityId = communityId
        self.useCases = useCases
        self.translationService = translationService
    }

    func load() async {
        do {
            settings = try await useCases.settings.load(communityId: communityId)
        } catch {
            errorMessage = message(for: error)
        }
    }

    func setWhoCanAddMembers(_ permission: CommunityPermission) {
        var updated = settings
        updated.whoCanAddMembers = permission
        save(updated)
    }

    func setWhoCanAddGroups(_ permission: CommunityPermission) {
        var updated = settings
        updated.whoCanAddGroups = permission
        save(updated)
    }

    func dismissError() {
        errorMessage = nil
    }

    /// Applied on screen first, then written. A permission switch that waits for
    /// a round trip reads as broken.
    private func save(_ updated: CommunitySettings) {
        let previous = settings
        settings = updated

        Task {
            do {
                try await useCases.settings.save(communityId: communityId, settings: updated)
            } catch {
                settings = previous
                errorMessage = message(for: error)
            }
        }
    }

    private func message(for error: Error) -> String {
        (error as? CommunityError)?.errorDescription ?? error.localizedDescription
    }
}
