//
//  UpdatesTabScreen.swift
//  WhatsAppClone
//
//  Created by Muharrem Efe Çayırbahçe on 5.01.2025.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

struct UpdatesTabScreen: View {
    @State private var searchText = ""
    let translationService: (any TranslationServiceProtocol)? = nil
    
    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack {
                List {
                    StatusSectionHeader(translationService: translationService)
                        .listRowBackground(Color.clear)
                    
                    StatusSection(translationService: translationService)
                    
                    Section {
                        RecentUpdatesItemView(translationService: translationService)
                    } header: {
                        Text(t(ChatTranslationKeys.STORIES_RECENT_UPDATES))
                    }
                    
                    Section {
                        ChannelListView(translationService: translationService)
                    } header: {
                        channelSectionHeader()
                    }
                    
                    
                }
                .listStyle(.grouped)
                .navigationTitle(t(ChatTranslationKeys.STORIES_UPDATES_TITLE))
                .searchable(text: $searchText)
            }
        } else {
            // Fallback on earlier versions
        }
    }
    
    private func channelSectionHeader() -> some View {
        HStack {
            Text(t(ChatTranslationKeys.STORIES_CHANNELS))
                .bold()
                .font(.title3)
                .textCase(nil)
//                .foregroundColor(.whatsAppBlack)
                
            Spacer()
            
            Button {
                
            } label: {
                Image(systemName: "plus")
                    .padding(7)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())
            }
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

extension UpdatesTabScreen {
    enum Constant {
        static let imageDimen: CGFloat = 55
    }
}

private struct StatusSectionHeader: View {
    let translationService: (any TranslationServiceProtocol)?
    
    init(translationService: (any TranslationServiceProtocol)?) {
        self.translationService = translationService
    }
    
    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "circle.dashed")
                .foregroundStyle(AppColors.primary)
                .imageScale(.large)
            (
                Text(t(ChatTranslationKeys.STORIES_STATUS_HEADER))
                
                +
                
                Text(" ")
                
                +
                
                Text(t(ChatTranslationKeys.STORIES_STATUS_PRIVACY))
                    .foregroundColor(AppColors.primary)
            )
            
            Image(systemName: "xmark")
                .foregroundStyle(.gray)
        }
        .padding()
//        .background(.whatsAppWhite)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

private struct StatusSection: View {
    let translationService: (any TranslationServiceProtocol)?
    
    init(translationService: (any TranslationServiceProtocol)?) {
        self.translationService = translationService
    }
    
    var body: some View {
        HStack {
            Circle()
                .frame(width: UpdatesTabScreen.Constant.imageDimen, height: UpdatesTabScreen.Constant.imageDimen)
            
            VStack(alignment: .leading) {
                Text(t(ChatTranslationKeys.STORIES_MY_STATUS))
                    .font(.callout)
                    .bold()
                    
                Text(t(ChatTranslationKeys.STORIES_ADD_TO_STATUS))
                    .foregroundColor(.gray)
                    .font(.system(size: 15))
            }
            
            Spacer()
            
            cameraButton()
            pencilButton()
        }
    }
    
    private func cameraButton() -> some View {
        Button {
            
        } label: {
            Image(systemName: "camera.fill")
                .padding(10)
                .background(Color(.systemGray5))
                .clipShape(Circle())
//                .bold()
        }
    }
    
    private func pencilButton() -> some View {
        Button {
            
        } label: {
            Image(systemName: "pencil")
                .padding(10)
                .background(Color(.systemGray5))
                .clipShape(Circle())
//                .bold()
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

private struct RecentUpdatesItemView: View {
    let translationService: (any TranslationServiceProtocol)?
    
    init(translationService: (any TranslationServiceProtocol)?) {
        self.translationService = translationService
    }
    
    var body: some View {
        HStack {
            Circle()
                .frame(width: UpdatesTabScreen.Constant.imageDimen, height: UpdatesTabScreen.Constant.imageDimen)
            
            VStack(alignment: .leading) {
                Text(t(ChatTranslationKeys.STORIES_SAMPLE_CONTACT))
                    .font(.callout)
                    .bold()
                
                Text(t(ChatTranslationKeys.STORIES_ONE_HOUR_AGO))
                    .foregroundColor(.gray)
                    .font(.system(size: 15))
            }
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

private struct ChannelListView: View {
    let translationService: (any TranslationServiceProtocol)?
    
    init(translationService: (any TranslationServiceProtocol)?) {
        self.translationService = translationService
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(t(ChatTranslationKeys.STORIES_CHANNELS_DESC))
                .foregroundColor(.gray)
                .font(.callout)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(0..<5) { _ in
                        SuggestedChannelItemView(translationService: translationService)
                    }
                }
            }
            
            Button(t(ChatTranslationKeys.STORIES_EXPLORE_MORE)) {
            }
            .tint(AppColors.primary)
//            .bold()
            .buttonStyle(.borderedProminent)
            .clipShape(Capsule())
            .padding(.vertical)
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

private struct SuggestedChannelItemView: View {
    let translationService: (any TranslationServiceProtocol)?
    
    init(translationService: (any TranslationServiceProtocol)?) {
        self.translationService = translationService
    }
    
    var body: some View {
        VStack {
            Circle()
                .frame(width: UpdatesTabScreen.Constant.imageDimen, height: UpdatesTabScreen.Constant.imageDimen)
            
            Text(t(ChatTranslationKeys.STORIES_CHANNEL_NAME))
            
            Button {
                
            } label: {
                Text(t(ChatTranslationKeys.STORIES_FOLLOW))
                    .bold()
                    .padding(5)
                    .frame(maxWidth: .infinity)
                    .background(AppColors.primary.opacity(0.2))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal)
        .padding(.vertical)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

//#Preview {
//    UpdatesTabScreen()
//}
