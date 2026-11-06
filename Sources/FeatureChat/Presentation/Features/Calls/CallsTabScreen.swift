
import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

struct CallsTabScreen: View {
    @State private var searchText = ""
    @State private var callFilter: CallFilter = .all
    @State private var showNewCallSheet = false
    @StateObject private var viewModel: CallsTabViewModel
    var contactsUseCase:ContactsUseCasesProtocol
    let translationService: (any TranslationServiceProtocol)?
    
    init(viewModel: CallsTabViewModel, contactsUseCase: ContactsUseCasesProtocol, translationService: (any TranslationServiceProtocol)? = nil) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.contactsUseCase = contactsUseCase
        self.translationService = translationService
    }
    
    private var displayedCalls: [GroupedCallItem] {
        let calls = viewModel.filteredGroupedCalls(missed: callFilter == .missed)
        if searchText.isEmpty { return calls }
        return calls.filter {
            $0.contactName.localizedCaseInsensitiveContains(searchText) ||
            $0.contactPhone.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        List {
            Section {
                CreateCallLinkSection(translationService: translationService)
            }
            
            Section {
                if viewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if displayedCalls.isEmpty {
                    emptyStateView()
                } else {
                    ForEach(displayedCalls) { group in
                        GroupedCallRowView(group: group) {
                            viewModel.startCall(
                                to: group.contactPhone,
                                isVideo: group.isVideo,
                                name: group.contactName,
                                image: group.contactImage,
                                conversationId: group.latestCall.conversationId,
                                userId: group.latestCall.userId
                            )
                        }
                    }
                }
            } header: {
                if !displayedCalls.isEmpty || viewModel.isLoading {
                    Text(t(ChatTranslationKeys.CALLS_RECENT))
                        .textCase(nil)
                        .font(.headline)
                }
            }
        }
        .navigationTitle(t(ChatTranslationKeys.CALLS_TITLE))
        .searchable(text: $searchText)
        .toolbar {
            leadingNavItem()
            trailingNavItem()
            principalNavItem()
        }
        .onAppear {
            viewModel.onAppear()
        }
        .chatAppearanceSheet(isPresented: $showNewCallSheet) {
            NewCallSheet(contactUseCases: contactsUseCase, translationService: translationService)
        }
    }
    
    @ViewBuilder
    private func emptyStateView() -> some View {
        VStack(spacing: 8) {
            Image(systemName: callFilter == .missed ? "phone.down" : "phone")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            
            Text(callFilter == .missed ? t(ChatTranslationKeys.CALLS_NO_MISSED) : t(ChatTranslationKeys.CALLS_NO_RECENT))
                .font(.headline)
            
            Text(t(ChatTranslationKeys.CALLS_EMPTY_SUBTITLE))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
    }
}

// MARK: - Toolbar

extension CallsTabScreen {
    @ToolbarContentBuilder
    private func trailingNavItem() -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showNewCallSheet = true
            } label: {
                Image(systemName: "phone.arrow.up.right")
            }
        }
    }
    
    @ToolbarContentBuilder
    private func leadingNavItem() -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(common("edit")) {
            }
        }
    }
    
    @ToolbarContentBuilder
    private func principalNavItem() -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker(t(ChatTranslationKeys.CALLS_CALL_HISTORY), selection: $callFilter) {
                ForEach(CallFilter.allCases) { item in
                    Text(title(for: item))
                        .tag(item)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .frame(width: 150)
        }
    }
    
    private enum CallFilter: String, CaseIterable, Identifiable {
        case all, missed
        var id: String { self.rawValue }
    }

    private func title(for filter: CallFilter) -> String {
        switch filter {
        case .all: return t(ChatTranslationKeys.CALLS_FILTER_ALL)
        case .missed: return t(ChatTranslationKeys.CALLS_FILTER_MISSED)
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}

// MARK: - Create Call Link

private struct CreateCallLinkSection: View {
    let translationService: (any TranslationServiceProtocol)?
    
    init(translationService: (any TranslationServiceProtocol)? = nil) {
        self.translationService = translationService
    }
    
    var body: some View {
        HStack {
            Image(systemName: "link")
                .padding(8)
                .background(Color(.systemGray6))
                .clipShape(Circle())
                .foregroundStyle(AppColors.primary)
            
            VStack(alignment: .leading) {
                Text(t(ChatTranslationKeys.CALLS_CREATE_LINK))
                    .foregroundStyle(AppColors.primary)
                
                Text(t(ChatTranslationKeys.CALLS_CREATE_LINK_DESC))
                    .foregroundStyle(.gray)
                    .font(.caption)
            }
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

// MARK: - Grouped Call Row (WhatsApp style)

struct GroupedCallRowView: View {
    let group: GroupedCallItem
    var onCallTapped: (() -> Void)?
    
    var body: some View {
        HStack(spacing: 12) {
            CircularProfileImageView(group.contactImage, size: .xSmall)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 0) {
                    Text(group.contactName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(group.isMissed ? .red : .primary)
                    
                    if group.count > 1 {
                        Text(" (\(group.count))")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
                
                HStack(spacing: 5) {
                    Image(systemName: group.callDirectionIcon)
                        .font(.system(size: 12))
                        .foregroundStyle(group.callDirectionColor)
                    
                    Text(group.callTypeLabel)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Text(group.shortTime)
                .foregroundStyle(.secondary)
                .font(.system(size: 14))
            
            Button {
                onCallTapped?()
            } label: {
                Image(systemName: group.isVideo ? "video" : "phone")
                    .foregroundStyle(AppColors.primary)
                    .font(.system(size: 16))
            }
        }
        .padding(.vertical, 2)
    }
}
