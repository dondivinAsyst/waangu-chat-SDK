//
//  GroupPendingJoinRequestsView.swift
//  FeatureChat
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

@available(iOS 17.0, *)
struct GroupPendingJoinRequestsView: View {
    @ObservedObject var viewModel: GroupPendingJoinRequestsViewModel
    let navigationCoord: ChatsTabCoordinator
    let translationService: (any TranslationServiceProtocol)?

    var body: some View {
        VStack(spacing: 0) {
            header

            Group {
                if viewModel.isLoading && viewModel.requests.isEmpty {
                    ProgressView(t(ChatTranslationKeys.JOIN_REQUESTS_LOADING))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.requests.isEmpty {
                    emptyState
                } else {
                    requestsList
                }
            }
        }
        .task {
            await viewModel.load()
        }
        .alert(common("error"), isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button(common("ok"), role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }

    private var header: some View {
        HStack {
            Button {
                navigationCoord.pop()
            } label: {
                Image(systemName: "chevron.backward")
                    .foregroundColor(AppColors.primary)
            }

            Spacer()

            VStack(spacing: 2) {
                Text(t(ChatTranslationKeys.JOIN_REQUESTS_TITLE))
                    .font(.headline)
                Text(viewModel.groupName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Color.clear.frame(width: 24, height: 24)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.badge.clock")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text(t(ChatTranslationKeys.JOIN_REQUESTS_EMPTY_TITLE))
                .font(.headline)
            Text(t(ChatTranslationKeys.JOIN_REQUESTS_EMPTY_SUBTITLE))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var requestsList: some View {
        List {
            ForEach(viewModel.requests) { request in
                joinRequestRow(request)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.load()
        }
    }

    private func joinRequestRow(_ request: GroupJoinRequest) -> some View {
        let isBusy = viewModel.actionInProgressId == request.id

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                CircularProfileImageView(request.avatar, size: .custom(44))

                VStack(alignment: .leading, spacing: 4) {
                    Text(request.name)
                        .font(.headline)
                    if let phone = request.phone, !phone.isEmpty {
                        Text(phone)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Text(request.requestedAt, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 12) {
                Button {
                    Task { await viewModel.decline(request) }
                } label: {
                    Text(t(ChatTranslationKeys.JOIN_REQUESTS_DECLINE))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)

                Button {
                    Task { await viewModel.approve(request) }
                } label: {
                    Text(t(ChatTranslationKeys.JOIN_REQUESTS_ACCEPT))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.primary)
                .disabled(isBusy)
            }
        }
        .padding(.vertical, 4)
        .opacity(isBusy ? 0.6 : 1)
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}
