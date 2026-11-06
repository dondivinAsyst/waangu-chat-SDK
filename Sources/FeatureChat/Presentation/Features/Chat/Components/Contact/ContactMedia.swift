//
//  ContactMedia.swift
//  Pods
//
//  Created by Asyst on 8/29/25.
//

import SwiftUI
import SDWebImageSwiftUI
import WaanguCoreKit

struct ContactMedia: View {
    let imageTransitionNamespace: Namespace.ID
    @Binding var isMediaLoaded: Bool
    @ObservedObject var contactProfileVm: ContactProfileViewModel
    @State private var selected = 0
    @State private var animationProgress: CGFloat = 0
    @State private var selectedMediaIndex: Int? = nil
    let uploadVM: FileUploadViewModel
    let translationService: (any TranslationServiceProtocol)?
    private var showAlbumView: Bool {
        selectedMediaIndex != nil
    }
    


    // Définir une grille avec 3 colonnes
    let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        NavigationView {
            VStack {
                
                Group {
                if selected == 0 {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(Array(contactProfileVm.mediaMessages.enumerated()), id: \.offset) { index, msg in

                                if let cachedImage = uploadVM.getCachedImage(key: msg.codeMessage) {
                                    Image(uiImage: cachedImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 100)
                                        .clipped()
                                        .contentShape(Rectangle())
                                        .matchedGeometryEffect(
                                            id: msg.id,
                                            in: imageTransitionNamespace,
                                            isSource: selectedMediaIndex == nil
                                        )
                                        .onTapGesture {
                                            selectedMediaIndex = index
                                        }
                                } else {
                                    Image(systemName: "photo.on.rectangle.angled.fill")
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 100)
                                        .foregroundColor(.gray.opacity(0.5))
                                }
                            }

//                            ForEach(contactProfileVm.mediaMessages.indices, id: \.self) { index in
//                                let msg = contactProfileVm.mediaMessages[index]
//
//                                if  let cachedImage = uploadVM.getCachedImage(key: msg.codeMessage)   {
//                                        Image(uiImage: cachedImage)
//                                            .resizable()
//                                            .placeholder {
//                                                Rectangle()
//                                                    .fill(Color.gray.opacity(0.3))
//                                                    .overlay(ProgressView())
//                                            }
//                                            .indicator(.activity)
//                                            .scaledToFill()
//                                            .frame(height: 100)
//                                            .clipped()
//                                            .contentShape(Rectangle())
//                                            .onTapGesture {
//                                                selectedMediaIndex = index
//                                            }
//                                 } else{
//                                   Image(systemName: "photo.on.rectangle.angled.fill")
//                                       .resizable()
//                               }
//
////                                if let urlString = msg.message.image ?? msg.message.video {
////                                    WebImage(url: URL(string: urlString))
////                                        .resizable()
////                                        .placeholder {
////                                            Rectangle()
////                                                .fill(Color.gray.opacity(0.3))
////                                                .overlay(ProgressView())
////                                        }
////                                        .indicator(.activity)
////                                        .scaledToFill()
////                                        .frame(height: 100)
////                                        .clipped()
////                                        .contentShape(Rectangle())
////                                        .onTapGesture {
////                                            selectedMediaIndex = index
////                                        }
////                                } else {
////                                    EmptyView()
////                                }
//                            }

                        }
                        .padding(0)
                      }
                    } else if selected == 1 {
                        Text(translationService?.resolve(key: ChatTranslationKeys.SHARED_MEDIA_TAB_LINKS, module: ChatTranslationKeys.MODULE).value ?? "Links")
                            .font(.title)
                            .padding()
                    } else if selected == 2 {
                        Text(translationService?.resolve(key: ChatTranslationKeys.SHARED_MEDIA_TAB_DOCS, module: ChatTranslationKeys.MODULE).value ?? "Docs")
                            .font(.title)
                            .padding()
                    }
                }
                
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button {
                    // props.onGoBackNavPressed([:])
                    isMediaLoaded.toggle()
                } label: {
                    Image(systemName: "chevron.backward")
                },
                trailing: Button(translationService?.resolve(key: "edit", module: ChatTranslationKeys.COMMON_MODULE).value ?? "Edit") {
                    // showEditContact = true
                }
            )
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Options", selection: $selected) {
                        Text(translationService?.resolve(key: ChatTranslationKeys.GALLERY_MEDIA, module: ChatTranslationKeys.MODULE).value ?? "Media").tag(0)
                        Text(translationService?.resolve(key: ChatTranslationKeys.GALLERY_LINKS, module: ChatTranslationKeys.MODULE).value ?? "Links").tag(1)
                        Text(translationService?.resolve(key: ChatTranslationKeys.GALLERY_DOCS, module: ChatTranslationKeys.MODULE).value ?? "Docs").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding()
                }
            }
        }
        .chatAppearanceFullScreenCover(isPresented:Binding(
            get: { selectedMediaIndex != nil },
            set: { newValue in
                if !newValue { selectedMediaIndex = nil }
            }
            )) {
           
                MediaAlbumView(
                    imageTransitionNamespace: imageTransitionNamespace,
                    userName: contactProfileVm.user?.name ?? "",
                    mediaMessages: contactProfileVm.mediaMessages,
                    selectedIndex: selectedMediaIndex!,
                    sourceFrame: .zero,
                    selectedMessage: contactProfileVm.mediaMessages[selectedMediaIndex!],
                    onIndexChange: { newValue in
                        debugLog("this is the new value: \(newValue)")
                    },
                    onDismiss: {
                        selectedMediaIndex = nil
                    },
                    translationService: translationService
                )
          }


    }
}
