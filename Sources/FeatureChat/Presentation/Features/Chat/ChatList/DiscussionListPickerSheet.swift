//
//  DiscussionListPickerSheet.swift
//  FeatureChat
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

struct DiscussionListPickerSheet: View {
    @ObservedObject var viewModel: ChannelTabViewModel
    let conversationId: String
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.customDiscussionLists.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(.largeTitle)
                            .foregroundStyle(AppColors.subtitleGray)
                        Text(t(ChatTranslationKeys.DISCUSSION_LIST_EMPTY_TITLE))
                            .font(.headline)
                        Text(t(ChatTranslationKeys.DISCUSSION_LIST_EMPTY_SUBTITLE))
                            .font(.subheadline)
                            .foregroundStyle(AppColors.subtitleGray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(viewModel.customDiscussionLists) { list in
                            listRow(list)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(t(ChatTranslationKeys.DISCUSSION_LIST_ADD_TO_LIST))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(common("done"), action: onDismiss)
                }
            }
            .onAppear {
                viewModel.reloadCustomDiscussionLists()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func listRow(_ list: DiscussionCustomList) -> some View {
        let isMember = list.conversationIds.contains(conversationId)
        return Button {
            viewModel.toggleDiscussionInList(
                conversationId,
                listId: list.id,
                listName: list.name
            )
        } label: {
            HStack {
                Text(list.name)
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                if isMember {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppColors.primary)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(AppColors.subtitleGray)
                }
            }
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        viewModel.translationService?.resolve(
            key: key,
            module: ChatTranslationKeys.MODULE,
            args: args
        ).value ?? key
    }

    private func common(_ key: String) -> String {
        viewModel.translationService?.resolve(
            key: key,
            module: ChatTranslationKeys.COMMON_MODULE
        ).value ?? fallbackCommonValue(for: key)
    }

    private func fallbackCommonValue(for key: String) -> String {
        switch key {
        case "done":
            return "Done"
        default:
            return key.capitalized
        }
    }
}
