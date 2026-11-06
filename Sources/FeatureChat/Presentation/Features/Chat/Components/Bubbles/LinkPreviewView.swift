import SwiftUI
import LinkPresentation
import Combine

// MARK: - Link Preview Data

struct LinkPreviewData: Equatable {
    let url: URL
    let title: String?
    let description: String?
    let image: UIImage?
    let domain: String

    static func == (lhs: LinkPreviewData, rhs: LinkPreviewData) -> Bool {
        lhs.url == rhs.url
    }
}

// MARK: - Link Preview Provider

final class LinkPreviewProvider: ObservableObject {

    static let shared = LinkPreviewProvider()

    private let memoryCache = NSCache<NSURL, LinkPreviewWrapper>()
    private let ioQueue = DispatchQueue(label: "com.waangu.linkpreview.io", qos: .utility)

    /// Eager, not `lazy`: this provider is a singleton read from the cooperative
    /// pool (`fetchPreview` → `loadFromDisk`) while `ioQueue` writes, and a
    /// `lazy var` has no synchronisation — two first-touches at once returned a
    /// half-initialised value and crashed in `appendingPathComponent`.
    private let diskCacheDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LinkPreviews", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {
        memoryCache.countLimit = 200
    }

    // MARK: - Public API

    func fetchPreview(for url: URL) async -> LinkPreviewData? {
        if let cached = memoryCache.object(forKey: url as NSURL) {
            return cached.data
        }

        if let diskCached = loadFromDisk(for: url) {
            memoryCache.setObject(LinkPreviewWrapper(data: diskCached), forKey: url as NSURL)
            return diskCached
        }

        let provider = LPMetadataProvider()
        provider.timeout = 8

        do {
            let metadata = try await provider.startFetchingMetadata(for: url)
            let image = await loadImage(from: metadata)

            let data = LinkPreviewData(
                url: url,
                title: metadata.title,
                description: metadata.value(forKey: "summary") as? String,
                image: image,
                domain: url.host ?? url.absoluteString
            )

            memoryCache.setObject(LinkPreviewWrapper(data: data), forKey: url as NSURL)
            saveToDisk(data)
            return data
        } catch {
            return nil
        }
    }

    // MARK: - Image loading

    private func loadImage(from metadata: LPLinkMetadata) async -> UIImage? {
        guard let imageProvider = metadata.imageProvider else { return nil }
        return await withCheckedContinuation { continuation in
            imageProvider.loadObject(ofClass: UIImage.self) { image, _ in
                continuation.resume(returning: image as? UIImage)
            }
        }
    }

    // MARK: - URL extraction

    static func extractFirstURL(from text: String?) -> URL? {
        guard let text = text else { return nil }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = detector?.firstMatch(in: text, options: [], range: range),
              let url = match.url else { return nil }
        return url
    }

    // MARK: - Disk Cache

    private func cacheKey(for url: URL) -> String {
        let raw = url.absoluteString.utf8
        var hash: UInt64 = 5381
        for byte in raw { hash = 127 &* (hash & 0x00ffffffffffffff) &+ UInt64(byte) }
        return String(hash, radix: 36)
    }

    private func saveToDisk(_ data: LinkPreviewData) {
        ioQueue.async { [weak self] in
            guard let self else { return }
            let key = self.cacheKey(for: data.url)

            let meta = DiskLinkMeta(
                url: data.url.absoluteString,
                title: data.title,
                desc: data.description,
                domain: data.domain
            )
            let metaURL = self.diskCacheDir.appendingPathComponent("\(key).json")
            if let encoded = try? JSONEncoder().encode(meta) {
                try? encoded.write(to: metaURL, options: .atomic)
            }

            if let image = data.image, let jpeg = image.jpegData(compressionQuality: 0.7) {
                let imgURL = self.diskCacheDir.appendingPathComponent("\(key).jpg")
                try? jpeg.write(to: imgURL, options: .atomic)
            }
        }
    }

    private func loadFromDisk(for url: URL) -> LinkPreviewData? {
        let key = cacheKey(for: url)
        let metaURL = diskCacheDir.appendingPathComponent("\(key).json")

        guard let jsonData = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(DiskLinkMeta.self, from: jsonData) else {
            return nil
        }

        let imgURL = diskCacheDir.appendingPathComponent("\(key).jpg")
        let image: UIImage? = FileManager.default.fileExists(atPath: imgURL.path)
            ? UIImage(contentsOfFile: imgURL.path)
            : nil

        return LinkPreviewData(
            url: url,
            title: meta.title,
            description: meta.desc,
            image: image,
            domain: meta.domain
        )
    }
}

private struct DiskLinkMeta: Codable {
    let url: String
    let title: String?
    let desc: String?
    let domain: String
}

private final class LinkPreviewWrapper {
    let data: LinkPreviewData
    init(data: LinkPreviewData) { self.data = data }
}

// MARK: - Link Preview View

@available(iOS 17.0, *)
struct LinkPreviewBubble: View {

    let url: URL
    @State private var preview: LinkPreviewData?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let preview = preview {
                VStack(alignment: .leading, spacing: 0) {
                    if let image = preview.image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxHeight: 160)
                            .clipped()
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        if let title = preview.title {
                            Text(title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }

                        Text(preview.domain)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .background(Color(.systemGray6).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onTapGesture {
                    UIApplication.shared.open(url)
                }
            } else if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(url.host ?? url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(8)
            }
        }
        .task {
            preview = await LinkPreviewProvider.shared.fetchPreview(for: url)
            isLoading = false
        }
    }
}

// MARK: - Compose Link Preview (shown above the input toolbar while typing)

struct ComposeLinkPreviewView: View {

    let url: URL
    let preview: LinkPreviewData?
    var onDismiss: () -> Void

    private var isLoading: Bool { preview == nil }

    var body: some View {
        HStack(spacing: 10) {
            if let image = preview?.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 52, height: 52)
                    .overlay(
                        Group {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "link")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(preview?.title ?? (url.host ?? url.absoluteString))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Text(preview?.domain ?? url.host ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .animation(.easeInOut(duration: 0.2), value: preview?.title)
    }
}
