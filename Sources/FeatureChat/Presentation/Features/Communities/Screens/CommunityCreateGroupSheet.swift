//
//  CommunityCreateGroupSheet.swift
//  FeatureChat
//

import SwiftUI
import WaanguCoreKit
import UIKit

/// Creating a group from inside a community.
///
/// The two screens are the app's own — `GroupPartnerPickerScreen` then
/// `NewGroupSetUpScreen`, the same pair the chats tab uses — so a group made
/// here is made exactly like a group made anywhere else. Only what happens
/// afterwards differs: it is attached to this community.
///
/// `ChatPartnerPickerScreen`, which normally wraps these two, is typed to the
/// chats tab's coordinator, so the stack is rebuilt here rather than dragging
/// that dependency into the communities tab.
@available(iOS 16.0, *)
struct CommunityCreateGroupSheet: View {

    @ObservedObject var viewModel: CommunityDetailViewModel
    /// The app's shared contact picker — the same instance the chats tab uses,
    /// so its loaded contacts are not fetched twice.
    @ObservedObject var partnerPicker: ChatPartnerPickerViewModel
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack(path: $partnerPicker.navStack) {
            GroupPartnerPickerScreen(
                viewModel: partnerPicker,
                translationService: viewModel.translationService
            )
            .navigationDestination(for: ChannelCreationRoute.self) { route in
                destination(for: route)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(common("cancel")) {
                        partnerPicker.resetNavigationState()
                        onDismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func destination(for route: ChannelCreationRoute) -> some View {
        switch route {
        case .groupPartnerPicker:
            GroupPartnerPickerScreen(
                viewModel: partnerPicker,
                translationService: viewModel.translationService
            )

        case .setUpGroupChat:
            NewGroupSetUpScreen(
                viewModel: partnerPicker,
                translationService: viewModel.translationService
            ) { groupName, members, image, settings in
                create(name: groupName, members: members, image: image, settings: settings)
            }
        }
    }

    private func create(
        name: String,
        members: [UserContactProps],
        image: UIImage?,
        settings: GroupSettings
    ) {
        partnerPicker.resetNavigationState()
        onDismiss()

        Task {
            await viewModel.createGroupAndAttach(
                name: name,
                members: members,
                image: image,
                settings: settings
            )
        }
    }

    private func common(_ key: String) -> String {
        viewModel.translationService?
            .resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}
