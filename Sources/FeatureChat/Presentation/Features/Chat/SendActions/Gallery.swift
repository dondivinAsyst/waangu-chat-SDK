//
//  Gallery.swift
//  chatpreview
//
//  Created by Asyst on 7/5/25.
//
import SwiftUI
import Photos
import SDWebImageSwiftUI
import WaanguSharedUI
import WaanguCoreKit


struct GalleryContentView: View {
    @ObservedObject var viewModel: GalleryViewModel
    let translationService: (any TranslationServiceProtocol)? = nil
    private let columns: [GridItem] = Array(repeating: .init(.flexible(), spacing: 1), count: 3)
    
    
    var body: some View {
        ZStack(alignment: .top) {
            
            // CONTENU QUI SCROLLE
            ScrollView {
                LazyVGrid(columns: columns, spacing: 1) {
                    ForEach(viewModel.images, id: \.id) { image in
                        GeometryReader { geometry in
                            GalleryImageCell(
                                isHidden: false,
                                image: image,
                                isSelected: viewModel.selectedImages.contains(where: { $0.id == image.id }),
                                onSelect: {
                                    viewModel.toggleSelection(for: image)
                                },
                                onPreview: {},
                                onPreviewWithRect: {
                                    viewModel.currentOverlayImage = image
                                }
                            )
                            .frame(height: UIScreen.main.bounds.width / 3)
                        }
                        .frame(height: UIScreen.main.bounds.width / 3)
                    }
                }
                .padding(.bottom, 60)
                .padding(.top, 60) // espace pour ne pas cacher le haut sous le header
            }
            
            // HEADER FIXE EN OVERLAY
            ZStack {
                BlurView(style: .systemMaterialLight)
                    .ignoresSafeArea(edges: .top)
                    .frame(height: 60)
                
                HStack {
                    Button(t(ChatTranslationKeys.GALLERY_CLOSE)) {
                        viewModel.selectedImages.removeAll()
                    }
                    .frame(width: 80, alignment: .leading)
//                    .fontWeight(.bold)
                    
                    Spacer()
                    selectedImageBadge()
                }
                .padding(.horizontal)
                
                Menu {
                    Button {
                        viewModel.loadImagesFromLibrary()
                    } label: {
                        AlbumMenuItem(
                            title: t(ChatTranslationKeys.GALLERY_ALL_PHOTOS),
                            count: viewModel.images.count,
                            image: viewModel.images.first?.asset.getThumbnail(),
                            translationService: translationService
                        )
                    }
                    ForEach(viewModel.albums) { album in
                        Button {
                            viewModel.loadImages(from: album)
                        } label: {
                            AlbumMenuItem(
                                title: album.title,
                                count: album.count,
                                image: album.coverImage,
                                translationService: translationService
                            )
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.selectedAlbum?.title ?? t(ChatTranslationKeys.GALLERY_ALL_PHOTOS))
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                }
                .menuStyle(BorderlessButtonMenuStyle())
                .font(.system(size: 14))
            }
            .frame(height: 60)
            .zIndex(1)
        }
        .onAppear {
            viewModel.requestPhotoLibraryAccess()
            viewModel.loadAlbums()
        }
        .onDisappear{
            viewModel.selectedImages.removeAll()
        }
                  
        .animation(.default, value: viewModel.currentOverlayImage)
    }

    
    func selectedImageBadge() -> some View {
        VStack {
            
            if viewModel.selectedImages.count > 0 {
                // Container for the badge
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    
                    let txt =  Text("\(viewModel.selectedImages.count)")
                    
                        .foregroundColor(.white)
                        .font(.system(size: 14, weight: .bold))
                    
                    if #available(iOS 16.0, *) {
                        txt.contentTransition(.numericText(countsDown: false))
                    } else {
                        txt
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(AppColors.primary)
                .clipShape(Capsule())
                .scaleEffect(viewModel.selectedImages.count > 0 ? 1 : 0.8)
                .opacity(viewModel.selectedImages.count > 0 ? 1 : 0)
                .animation(
                    .interpolatingSpring(stiffness: 300, damping: 15)
                    .delay(0.1),
                    value: viewModel.selectedImages.count
                )
            }else{
//                searchButton()
            }
        }
        .frame(width: 80, alignment: .trailing)
        .contentShape(Rectangle())
        .onTapGesture {
//            onPressBadge()
//            isBadge = true
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

struct GalleryImageCell: View {
    let isHidden: Bool
    let image: GalleryImage
    let isSelected: Bool
    let onSelect: () -> Void
    let onPreview: () -> Void
    let onPreviewWithRect: () -> Void

    @State private var uiImage: UIImage? = nil
    let cellSize: CGFloat = UIScreen.main.bounds.width / 3

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let uiImage = uiImage {
                if isHidden {
                    Color.black
                        .aspectRatio(contentMode: .fill)
                        .frame(width: cellSize, height: cellSize)
                } else {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: cellSize, height: cellSize)
                        .clipped()
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onPreviewWithRect)
                }
            } else {
                Color.gray.opacity(0.1)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: cellSize, height: cellSize)
            }

            if !isHidden {
                Button(action: onSelect) {
                    ZStack {
                        Circle()
                            .strokeBorder(Color.white, lineWidth: 2)
                            .background(Circle().fill(isSelected ? AppColors.primary : Color.black.opacity(0.5)))
                            .frame(width: 24, height: 24)

                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(6)
            }
        }
        .onAppear { loadImage() }
    }
    
    private func loadImage() {
        DispatchQueue.global(qos: .userInitiated).async {
            let manager = PHImageManager.default()
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast

            manager.requestImage(
                for: image.asset,
                targetSize: CGSize(width: 200, height: 200),
                contentMode: .aspectFill,
                options: options
            ) { result, _ in
                DispatchQueue.main.async {
                    self.uiImage = result
                }
            }
        }
    }
}
