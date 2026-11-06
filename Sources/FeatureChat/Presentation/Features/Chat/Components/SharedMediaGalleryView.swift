import SwiftUI
import WaanguCoreKit

enum SharedMediaTab: String, CaseIterable {
    case media = "Media"
    case docs = "Docs"
    case links = "Links"
}

@available(iOS 17.0, *)
struct SharedMediaGalleryView: View {

    let conversationId: String
    let messages: [MessageDataItem]
    let translationService: (any TranslationServiceProtocol)? = nil
    @State private var selectedTab: SharedMediaTab = .media

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(SharedMediaTab.allCases, id: \.self) { tab in
                    Text(tabTitle(tab)).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            switch selectedTab {
            case .media:
                mediaGrid
            case .docs:
                docsList
            case .links:
                linksList
            }
        }
        .navigationTitle(t(ChatTranslationKeys.SHARED_MEDIA_TITLE))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Media Grid

    private var mediaGrid: some View {
        let mediaMessages = messages.filter {
            ($0.typeMessage == .IMAGE || $0.typeMessage.isVideo) && !$0.isViewOnce
        }

        return Group {
            if mediaMessages.isEmpty {
                emptyState(icon: "photo.on.rectangle", text: t(ChatTranslationKeys.SHARED_MEDIA_EMPTY_MEDIA))
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                        ForEach(mediaMessages, id: \.codeMessage) { msg in
                            mediaCell(msg)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func mediaCell(_ message: MessageDataItem) -> some View {
        ZStack {
            if let uiImage = message.message.UIimage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(minHeight: 100)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .overlay {
                        Image(systemName: message.typeMessage.isVideo ? "video.fill" : "photo")
                            .foregroundStyle(.secondary)
                    }
            }

            if message.typeMessage.isVideo {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "play.fill")
                            .font(.caption2)
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(4)
                }
            }
        }
        .frame(minHeight: 100)
    }

    // MARK: - Documents List

    private var docsList: some View {
        let docMessages = messages.filter { $0.typeMessage == .DOCUMENT }

        return Group {
            if docMessages.isEmpty {
                emptyState(icon: "doc.text", text: t(ChatTranslationKeys.SHARED_MEDIA_EMPTY_DOCS))
            } else {
                List(docMessages, id: \.codeMessage) { msg in
                    HStack(spacing: 12) {
                        Image(systemName: docIcon(for: msg.message.mimeType))
                            .font(.title2)
                            .foregroundStyle(.blue)
                            .frame(width: 40)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(msg.message.fileName ?? t(ChatTranslationKeys.GALLERY_DOCUMENT))
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            HStack {
                                Text(formattedSize(msg.message.size))
                                Text("·")
                                Text(msg.displayTime)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Links List

    private var linksList: some View {
        let linkMessages = messages.filter {
            LinkPreviewProvider.extractFirstURL(from: $0.message.text) != nil
        }

        return Group {
            if linkMessages.isEmpty {
                emptyState(icon: "link", text: "No links shared yet")
            } else {
                List(linkMessages, id: \.codeMessage) { msg in
                    if let url = LinkPreviewProvider.extractFirstURL(from: msg.message.text) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(url.host ?? url.absoluteString)
                                .font(.subheadline.weight(.medium))
                            Text(msg.message.text ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private func emptyState(icon: String, text: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
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
        return "doc"
    }

    private func formattedSize(_ size: Int?) -> String {
        guard let bytes = size, bytes > 0 else { return "" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func tabTitle(_ tab: SharedMediaTab) -> String {
        switch tab {
        case .media: return t(ChatTranslationKeys.SHARED_MEDIA_TAB_MEDIA)
        case .docs: return t(ChatTranslationKeys.SHARED_MEDIA_TAB_DOCS)
        case .links: return t(ChatTranslationKeys.SHARED_MEDIA_TAB_LINKS)
        }
    }
}
