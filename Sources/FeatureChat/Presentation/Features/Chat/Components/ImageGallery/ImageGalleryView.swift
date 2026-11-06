import SwiftUI
import WaanguCoreKit

struct CachedMediaItem: Identifiable, Equatable {
    var codeMessage: String
    var image: UIImage?
    var videoURL: URL?
    var typeMessage: MessageTypeProps
    var senderName: String
    var displayTime: String
    var videoDuration: TimeInterval?
    var id: String { codeMessage }

    var isVideo: Bool { typeMessage.isVideo }
}

/// Shared-media grid for a contact profile: media, links and documents.
///
/// Tapping a tile opens `MediaViewerController` through the same hero transition
/// the chat room uses — this view no longer owns a carousel of its own.
struct ImageGallery: View {
    @Binding var isMediaSheetOpened: Bool
    var contactVM: ContactProfileViewModel
    var uploadVM: FileUploadViewModel
    var chatRoomVM: ChatRoomViewModel
    let userName: String

    @State private var selected = 0
    @State private var docPreviewURL: URL?
    @State private var showDocPreview: Bool = false
    @State private var mediaViewerRequest: MediaViewerRequest?

    // MARK: - Load cached images

    private func loadCachedImages() {
        if !contactVM.cachedImagesData.isEmpty { return }
        Task { @MainActor in
            for media in contactVM.mediaMessages {
                guard let image = uploadVM.getCachedImage(key: media.codeMessage) else { continue }
                guard !contactVM.cachedImagesData.contains(where: { $0.id == media.codeMessage }) else { continue }

                let videoURL: URL? = media.typeMessage.isVideo
                    ? DiskMediaManager.shared.loadVideoFromDisk(fileName: media.codeMessage, pathName: .CHAT)
                    : nil

                contactVM.cachedImagesData.append(
                    CachedMediaItem(
                        codeMessage: media.codeMessage,
                        image: image,
                        videoURL: videoURL,
                        typeMessage: media.typeMessage,
                        senderName: media.senderName,
                        displayTime: media.displayTime,
                        videoDuration: media.message.videoDuration
                    )
                )
            }
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationView {
            content
        }
    }

    private var content: some View {
        ScrollView {
            if contactVM.cachedImagesData.isEmpty {
                SkeletonGrid(CellNumber: contactVM.mediaMessages.count)
            } else {
                switch selected {
                case 0: mediaTab
                case 1: linksTab
                default: docsTab
                }
            }
        }
        .onAppear {
            loadCachedImages()
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarItems(
            leading: Button {
                isMediaSheetOpened.toggle()
            } label: {
                Image(systemName: "chevron.backward")
            },
            trailing: Button(t(ChatTranslationKeys.GALLERY_EDIT)) {
                // Edit action
            }
        )
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Options", selection: $selected) {
                    Text(t(ChatTranslationKeys.GALLERY_MEDIA)).tag(0)
                    Text(t(ChatTranslationKeys.GALLERY_LINKS)).tag(1)
                    Text(t(ChatTranslationKeys.GALLERY_DOCS)).tag(2)
                }
                .pickerStyle(.segmented)
                .padding()
            }
        }
        .chatAppearanceSheet(isPresented: $showDocPreview) {
            if let url = docPreviewURL {
                DocumentPreviewSheet(url: url)
            }
        }
        .mediaViewer(
            $mediaViewerRequest,
            userName: userName,
            translate: { key, args in
                chatRoomVM.translationService?
                    .resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
            },
            onDelete: { item, onlyMe in
                guard let message = contactVM.mediaMessages.first(where: { $0.codeMessage == item.id }) else { return }
                contactVM.deleteMessages(onlyMe: onlyMe, message: message)
            }
        )
    }

    // MARK: - Media Tab

    private var mediaTab: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3),
            spacing: 2
        ) {
            ForEach(contactVM.cachedImagesData) { media in
                if let image = media.image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                        .overlay {
                            if media.isVideo {
                                videoBadge(duration: media.videoDuration)
                            }
                        }
                        .heroAnchor(id: media.id, image: image)
                        .contentShape(Rectangle())
                        .onTapGesture { openViewer(at: media.codeMessage) }
                }
            }
        }
        .padding(2)
    }

    private func openViewer(at codeMessage: String) {
        guard let message = contactVM.mediaMessages.first(where: { $0.codeMessage == codeMessage }) else { return }
        mediaViewerRequest = ChatRoomMediaViewerCoordinator.makeRequest(
            tapped: message,
            in: contactVM.mediaMessages,
            thumbnailProvider: {
                ChatImageMemoryCache.shared.image(forKey: $0)
                    ?? DiskMediaManager.shared.loadImageFromDisk(fileName: $0, pathName: .CHAT)
            }
        )
    }

    @ViewBuilder
    private func videoBadge(duration: TimeInterval?) -> some View {
        ZStack {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 28))
                .foregroundColor(.white.opacity(0.9))
                .shadow(radius: 3)

            VStack {
                Spacer()
                HStack {
                    HStack(spacing: 2) {
                        Image(systemName: "video.fill")
                        if let duration, duration > 0 {
                            Text(String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60))
                        }
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(Color.black.opacity(0.5)).clipShape(Capsule())
                    .padding(4)
                    Spacer()
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Links Tab

    @ViewBuilder
    private var linksTab: some View {
        let linkMessages = contactVM.linksMessages
        if linkMessages.isEmpty {
            emptyTabState(icon: "link", text: t(ChatTranslationKeys.GALLERY_NO_LINKS))
        } else {
            LazyVStack(spacing: 0) {
                ForEach(linkMessages, id: \.codeMessage) { msg in
                    if let url = resolvedLinkURL(for: msg) {
                        LinkRowView(url: url, messageText: msg.message.text, displayTime: msg.displayTime)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        Divider().padding(.leading, 12)
                    }
                }
            }
        }
    }

    // MARK: - Docs Tab

    @ViewBuilder
    private var docsTab: some View {
        let docMessages = contactVM.documentMessages
        if docMessages.isEmpty {
            emptyTabState(icon: "doc.text", text: t(ChatTranslationKeys.GALLERY_NO_DOCS))
        } else {
            LazyVStack(spacing: 0) {
                ForEach(docMessages, id: \.codeMessage) { msg in
                    HStack(spacing: 12) {
                        Image(systemName: docIcon(for: msg.message.mimeType))
                            .font(.title2)
                            .foregroundStyle(.blue)
                            .frame(width: 40, height: 40)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(msg.message.fileName ?? t(ChatTranslationKeys.GALLERY_DOCUMENT))
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            HStack(spacing: 4) {
                                if let size = msg.message.size, size > 0 {
                                    Text(formattedSize(size))
                                }
                                Text(msg.displayTime)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let fileURL = resolvedLocalDocumentURL(for: msg) {
                            docPreviewURL = fileURL
                            showDocPreview = true
                        }
                    }

                    Divider().padding(.leading, 64)
                }
            }
        }
    }

    // MARK: - Helpers

    private func emptyTabState(icon: String, text: String) -> some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 80)
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func docIcon(for mimeType: String?) -> String {
        guard let mime = mimeType else { return "doc" }
        if mime.contains("pdf") { return "doc.text.fill" }
        if mime.contains("word") || mime.contains("doc") { return "doc.richtext" }
        if mime.contains("sheet") || mime.contains("xls") { return "tablecells" }
        if mime.contains("presentation") || mime.contains("ppt") { return "doc.text.image" }
        return "doc"
    }

    private func formattedSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func resolveDocExtension(from fileName: String?) -> String {
        guard let name = fileName else { return "" }
        return (name as NSString).pathExtension.lowercased()
    }

    private func resolvedLinkURL(for msg: MessageDataItem) -> URL? {
        if let fromText = LinkPreviewProvider.extractFirstURL(from: msg.message.text) {
            return fromText
        }
        let trimmed = msg.message.url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    /// Same resolution as `BubbleDocumentView` so PDFs and cached files open from the gallery.
    private func resolvedLocalDocumentURL(for message: MessageDataItem) -> URL? {
        let raw = message.message.file?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let originalURL: URL? = {
            guard !raw.isEmpty else { return nil }
            if let url = URL(string: raw), url.scheme != nil {
                return url
            }
            return URL(fileURLWithPath: raw)
        }()

        if let url = originalURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        let ext = resolveDocExtension(from: message.message.fileName)
        if let url = originalURL, ext.isEmpty {
            let inferred = url.pathExtension.lowercased()
            if !inferred.isEmpty,
               let diskURL = DiskMediaManager.shared.loadFileFromDisk(
                   fileName: message.codeMessage,
                   ext: inferred,
                   pathName: .CHAT
               ) {
                return diskURL
            }
        }

        if let diskURL = DiskMediaManager.shared.loadFileFromDisk(
            fileName: message.codeMessage,
            ext: ext,
            pathName: .CHAT
        ) {
            return diskURL
        }

        if let storedName = originalURL?.deletingPathExtension().lastPathComponent,
           !storedName.isEmpty,
           let diskURL = DiskMediaManager.shared.loadFileFromDisk(
               fileName: storedName,
               ext: ext,
               pathName: .CHAT
           ) {
            return diskURL
        }

        return originalURL
    }

    private func t(_ key: String, args: [String] = []) -> String {
        chatRoomVM.translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

// MARK: - Link Row View

private struct LinkRowView: View {
    let url: URL
    let messageText: String
    let displayTime: String

    @State private var preview: LinkPreviewData?

    var body: some View {
        HStack(spacing: 12) {
            if let image = preview?.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "link")
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(preview?.title ?? url.host ?? url.absoluteString)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)

                Text(url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .lineLimit(1)

                Text(displayTime)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            UIApplication.shared.open(url)
        }
        .task {
            preview = await LinkPreviewProvider.shared.fetchPreview(for: url)
        }
    }
}
