//
//  Gallery.swift
//  chatpreview
//
//  Created by Asyst on 7/5/25.
//
import SwiftUI
import Photos
import SDWebImageSwiftUI
import WaanguCoreKit

struct GalleryView: View {
    @ObservedObject var viewModel: PHMediaManagerViewModel
    var selectingEnded: (([GalleryMedia]) -> Void)?
    var onDirectSelect: ((GalleryMedia) -> Void)?
    let translationService: (any TranslationServiceProtocol)?
    private let columns: [GridItem] = Array(repeating: .init(.flexible(), spacing: 1), count: 3)
    @State private var openingMediaId: String?
    
    init(
        viewModel: PHMediaManagerViewModel,
        translationService: (any TranslationServiceProtocol)? = nil,
        selectingEnded: (([GalleryMedia]) -> Void)? = nil,
        onDirectSelect: ((GalleryMedia) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.translationService = translationService
        self.selectingEnded = selectingEnded
        self.onDirectSelect = onDirectSelect
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            
            // CONTENU QUI SCROLLE
            ScrollView {
                LazyVGrid(columns: columns, spacing: 1) {
                    ForEach(viewModel.mediaItems, id: \.id) { media in
                        GeometryReader { geometry in
                            GalleryMediaCell(
                                isHidden: false,
                                media: media,
                                videoBadgeLabel: t(ChatTranslationKeys.GALLERY_VIDEO_BADGE),
                                isSelected: viewModel.selectedMedia.contains(where: { $0.id == media.id }),
                                isOpening: openingMediaId == media.id,
                                onSelect: {
                                    viewModel.toggleSelection(for: media)
                                },
                                onPreview: {},
                                onPreviewWithRect: {
                                    if let onDirectSelect {
                                        openingMediaId = media.id
                                        viewModel.prepareMediaForPreview(media) { prepared in
                                            Task { @MainActor in
                                                onDirectSelect(prepared)
                                                openingMediaId = nil
                                            }
                                        }
                                    } else {
                                        viewModel.currentOverlayMedia = media
                                    }
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
                BlurView(style: .systemMaterial)
                    .ignoresSafeArea(edges: .top)
                    .frame(height: 60)
                
                HStack {
                    Button(t(ChatTranslationKeys.GALLERY_CLOSE)) {
                        viewModel.selectedMedia.removeAll()
                    }
                    .frame(width: 80, alignment: .leading)
                    
                    Spacer()
                    selectedMediaBadge(selectingEnded: {
                        selectingEnded?(viewModel.selectedMedia)
                    })
                }
                .padding(.horizontal)
                
                Menu {
                    Button {
                        viewModel.loadMediaFromLibrary()
                    } label: {
                        AlbumMenuItems(
                            title: t(ChatTranslationKeys.GALLERY_ALL_MEDIA),
                            count: viewModel.mediaItems.count,
                            image: getCoverImage(for: viewModel.mediaItems.first)
                        )
                    }
                    ForEach(viewModel.albums) { album in
                        Button {
                            viewModel.loadMedia(from: album)
                        } label: {
                            AlbumMenuItems(
                                title: album.title,
                                count: album.count,
                                image: getCoverImage(for: album)
                            )
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.selectedAlbum?.title ?? t(ChatTranslationKeys.GALLERY_ALL_MEDIA))
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
        .onDisappear {
            viewModel.selectedMedia.removeAll()
            openingMediaId = nil
        }
        .background(Color(.systemGray6))
    }

    func selectedMediaBadge( selectingEnded: @escaping () -> Void) -> some View {
        VStack {
            if viewModel.selectedMedia.count > 0 {
                // Container for the badge
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    
                    let txt = Text("\(viewModel.selectedMedia.count)")
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
                .background(Color.blue)
                .clipShape(Capsule())
                .scaleEffect(viewModel.selectedMedia.count > 0 ? 1 : 0.8)
                .opacity(viewModel.selectedMedia.count > 0 ? 1 : 0)
                .animation(
                    .interpolatingSpring(stiffness: 300, damping: 15)
                    .delay(0.1),
                    value: viewModel.selectedMedia.count
                )
            }
        }
        .frame(width: 80, alignment: .trailing)
        .contentShape(Rectangle())
        .onTapGesture {
            // Action when badge is tapped
            selectingEnded()
        }
    }
    
    private func getCoverImage(for media: GalleryMedia?) -> UIImage? {
        return media?.highQualityImage
    }
    
    private func getCoverImage(for album: MediaAlbum?) -> UIImage? {
        // Si votre MediaAlbum a une propriété coverImage, utilisez-la
        // Sinon, vous devrez peut-être adapter votre MediaAlbum pour inclure une image de couverture
        return nil // À adapter selon votre implémentation
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

struct GalleryMediaCell: View {
    let isHidden: Bool
    let media: GalleryMedia
    let videoBadgeLabel: String
    let isSelected: Bool
    var isOpening: Bool = false
    let onSelect: () -> Void
    let onPreview: () -> Void
    let onPreviewWithRect: () -> Void

    @State private var uiImage: UIImage? = nil
    @State private var thumbnailBase64: String? = nil
    @State private var suppressMediaTap = false
    let cellSize: CGFloat = UIScreen.main.bounds.width / 3

    var body: some View {
        ZStack {
            ZStack {
                mediaThumbnail
                if isSelected || isOpening {
                    Color.black.opacity(0.35)
                        .allowsHitTesting(false)
                }
                if isOpening {
                    ProgressView()
                        .tint(.white)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: cellSize, height: cellSize)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isOpening, !suppressMediaTap else { return }
                onPreviewWithRect()
            }

            if media.type == .video {
                videoBadge
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !isHidden {
                selectionButton
            }
        }
        .onAppear { loadThumbnail() }
    }

    @ViewBuilder
    private var mediaThumbnail: some View {
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
            }
        } else if let thumbnailBase64 = thumbnailBase64 {
            WebImage(url: URL(string: thumbnailBase64))
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: cellSize, height: cellSize)
        } else {
            Color.gray.opacity(0.1)
                .aspectRatio(contentMode: .fill)
                .frame(width: cellSize, height: cellSize)
        }
    }
    
    private var videoBadge: some View {
        VStack {
            Spacer()
            HStack {
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                Text(videoBadgeLabel)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.7))
            .cornerRadius(4)
            .padding(4)
        }
    }
    
    private var selectionButton: some View {
        Button {
            suppressMediaTap = true
            onSelect()
            DispatchQueue.main.async {
                suppressMediaTap = false
            }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 2)
                    .background(Circle().fill(isSelected ? Color.blue : Color.black.opacity(0.5)))
                    .frame(width: 24, height: 24)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func loadThumbnail() {
        // Utilise le PHMediaManager pour charger le thumbnail
        let size = CGSize(width: 200, height: 200)
        
        // Pour une meilleure performance, vous pourriez injecter le mediaManager dans la cellule
        // ou passer une closure depuis le ViewModel
        DispatchQueue.global(qos: .userInitiated).async {
            let manager = PHImageManager.default()
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true

            manager.requestImage(
                for: media.asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { result, _ in
                DispatchQueue.main.async {
                    self.uiImage = result
                }
            }
        }
        
        // Alternative: utiliser la méthode du ViewModel pour les thumbnails base64
        // viewModel.generateAndSaveThumbnail(for: media.asset) { base64 in
        //     DispatchQueue.main.async {
        //         self.thumbnailBase64 = base64
        //     }
        // }
    }

}



// Structure pour les éléments de menu d'album (à adapter si nécessaire)
struct AlbumMenuItems: View {
    let title: String
    let count: Int
    let image: UIImage?
    
    var body: some View {
        HStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipped()
                    .cornerRadius(4)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 40, height: 40)
                    .cornerRadius(4)
            }
            
            VStack(alignment: .leading) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Text("\(count)")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            
            Spacer()
        }
        .frame(width: 200)
    }
}

