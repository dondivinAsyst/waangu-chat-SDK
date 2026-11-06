import SwiftUI
import Combine
import WaanguSharedUI
import WaanguCoreKit

// MARK: - Unified Transfer State

public enum MediaTransferState: Equatable {
    case idle
    case loading
    case transferring(progress: Double)
    case success
    case failure(error: String)
}

extension MessageDataItem {

    /// Whether this photo or video still has to be moved before it can be shown.
    ///
    /// Asked of the file, not of who sent the message. Keying this on `direction`
    /// quietly assumed that "I sent it" means "this device produced it and still
    /// has it" — which is false the moment the account is signed in anywhere else.
    /// Media sent from the web or a second phone arrives with `senderId` equal to
    /// our own, so it read as outgoing, as nothing left to do, and rendered as a
    /// bare thumbnail with no way to fetch the real file.
    ///
    /// The same reasoning covers a subtler case that was always broken: media this
    /// device really did send, whose cached copy the system has since evicted —
    /// `.caches` is reclaimable at any time.
    ///
    /// This is also what keeps a batch's single retry button honest: it acts on the
    /// items that answer true here and leaves the rest alone.
    ///
    /// Deliberately does **not** ask whether a remote address can be resolved.
    /// Gating it on that meant any media whose URL this app failed to recognise
    /// showed no control at all — silence, and no way for the user to even try. A
    /// control that attempts and reports a failure beats that every time: it is
    /// visible, and it is retryable.
    var mediaNeedsTransfer: Bool {
        if message.shouldUploadDownload || message.shouldRetry { return true }
        return ChatMediaDiskResolver.localMediaURL(for: self) == nil
    }

    /// Whether moving this media means fetching it rather than sending it.
    ///
    /// Only a message this device is still trying to hand to the server counts as
    /// an upload. Everything else — someone else's media, and our own account's
    /// media from another device — has to come down.
    var mediaTransferIsDownload: Bool {
        !message.shouldUploadDownload
    }

    /// Where to fetch this media from, when it has to be fetched.
    ///
    /// Deliberately not `image ?? remoteUri`, which is what the download callers
    /// used to do. Those fields are not addresses — they hold whatever the message
    /// last knew about its media, and for anything this device queued that is a
    /// local filesystem path. `image` is only patched to the CDN URL once the
    /// upload lands, so a message caught between those two states hands its
    /// downloader a path like `/var/mobile/.../IMG_0042.jpg`, which fails looking
    /// exactly like a network error.
    ///
    /// `remoteUri` is asked first because it is the one field that only ever means
    /// "the server's copy".
    ///
    /// Candidates are rejected for *looking local*, rather than accepted for
    /// matching a list of known schemes. Requiring http(s) was the stricter rule
    /// and the wrong one: anything the backend serves over another scheme was
    /// silently discarded, and the caller could not tell that from "there is no
    /// media here".
    var remoteMediaURLString: String? {
        let candidates = [
            message.remoteUri,
            message.image,
            message.video,
            message.audio,
            message.file,
            message.url
        ]

        for candidate in candidates {
            guard let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty,
                  !Self.looksLocal(trimmed)
            else { continue }
            return trimmed
        }

        return nil
    }

    /// Whether this string is a path on this device rather than an address.
    ///
    /// An absolute path, a `file://` URL, or a bare name with no scheme at all —
    /// each of which a downloader can do nothing with.
    private static func looksLocal(_ value: String) -> Bool {
        if value.hasPrefix("/") { return true }
        if let scheme = URL(string: value)?.scheme?.lowercased() {
            return scheme == "file"
        }
        return true
    }
}

// MARK: - Disk helpers (shared by transfer button + document bubble)

enum ChatMediaDiskResolver {

    /// The on-disk copy of a photo or video, if this device already has one.
    ///
    /// One answer to "is this here", rather than the three the grid used to use —
    /// `DiskMediaManager` in one place, `checkIfCached` in another, `FileManager`
    /// in a third — which could disagree about the same file.
    static func localMediaURL(for message: MessageDataItem) -> URL? {
        let code = message.codeMessage
        guard !code.isEmpty else { return nil }

        if message.typeMessage.isVideo {
            guard let url = DiskMediaManager.shared.loadVideoFromDisk(fileName: code, pathName: .CHAT),
                  FileManager.default.fileExists(atPath: url.path) else { return nil }
            return url
        }

        // Returns nil for a file that is not there — it probes jpg then png with
        // `fileExists`, so a non-nil result really does mean present.
        return DiskMediaManager.shared.imageURL(for: code, pathName: .CHAT)
    }

    static func documentExtension(fileName: String?, filePath: String?, mimeType: String? = nil) -> String {
        mediaExtension(fileName: fileName, filePath: filePath, mimeType: mimeType, fallback: "")
    }

    /// Voice notes are typically Opus in an Ogg container; prefer file metadata, then mime, then `opus`.
    static func audioExtension(
        fileName: String?,
        filePath: String?,
        mimeType: String?
    ) -> String {
        mediaExtension(fileName: fileName, filePath: filePath, mimeType: mimeType, fallback: "opus")
    }

    private static func mediaExtension(
        fileName: String?,
        filePath: String?,
        mimeType: String?,
        fallback: String
    ) -> String {
        if let name = fileName {
            let ext = (name as NSString).pathExtension.lowercased()
            if !ext.isEmpty { return ext }
        }

        let raw = filePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !raw.isEmpty {
            if let url = URL(string: raw), url.scheme != nil {
                let ext = url.pathExtension.lowercased()
                // Strip query/fragment-style junk: "file.opus?token=…" already handled by pathExtension
                if !ext.isEmpty, ext.count <= 5 { return ext }
            } else {
                let ext = (raw as NSString).pathExtension.lowercased()
                if !ext.isEmpty { return ext }
            }
        }

        if let mime = mimeType?.lowercased() {
            switch mime {
            case "audio/ogg", "audio/opus": return "opus"
            case "audio/mpeg", "audio/mp3": return "mp3"
            case "audio/mp4", "audio/m4a", "audio/x-m4a": return "m4a"
            case "audio/wav", "audio/x-wav": return "wav"
            case "application/pdf": return "pdf"
            case "application/msword": return "doc"
            case "application/vnd.openxmlformats-officedocument.wordprocessingml.document": return "docx"
            default:
                if let subtype = mime.split(separator: "/").last, subtype.count <= 5 {
                    let cleaned = subtype.replacingOccurrences(of: "x-", with: "")
                    if !cleaned.isEmpty { return cleaned }
                }
            }
        }

        return fallback
    }

    static func localDocumentURL(
        codeMessage: String,
        fileName: String?,
        filePath: String?,
        mimeType: String? = nil
    ) -> URL? {
        let ext = documentExtension(fileName: fileName, filePath: filePath, mimeType: mimeType)
        let raw = filePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let originalURL: URL? = if !raw.isEmpty {
            if let url = URL(string: raw), url.scheme != nil {
                url
            } else {
                URL(fileURLWithPath: raw)
            }
        } else {
            nil
        }

        if let url = originalURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        if !ext.isEmpty, !codeMessage.isEmpty,
           let diskURL = DiskMediaManager.shared.loadFileFromDisk(
               fileName: codeMessage, ext: ext, pathName: .CHAT
           ) {
            return diskURL
        }

        if let storedName = originalURL?.deletingPathExtension().lastPathComponent,
           !storedName.isEmpty, !ext.isEmpty,
           let diskURL = DiskMediaManager.shared.loadFileFromDisk(
               fileName: storedName, ext: ext, pathName: .CHAT
           ) {
            return diskURL
        }

        return nil
    }

    static func localAudioURL(
        codeMessage: String,
        fileName: String?,
        filePath: String?,
        mimeType: String?
    ) -> URL? {
        let raw = filePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let originalURL: URL? = if !raw.isEmpty {
            if let url = URL(string: raw), url.scheme != nil {
                url
            } else {
                URL(fileURLWithPath: raw)
            }
        } else {
            nil
        }

        if let url = originalURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        let ext = audioExtension(fileName: fileName, filePath: filePath, mimeType: mimeType)
        guard !codeMessage.isEmpty else { return nil }

        if let diskURL = DiskMediaManager.shared.loadAudioFromDisk(
            fileName: codeMessage,
            ext: ext,
            pathName: .CHAT
        ) {
            return diskURL
        }

        // Legacy / alternate extension probes used by BubbleVoiceView
        for candidate in [ext, "opus", "ogg", "m4a", "mp3"] where !candidate.isEmpty {
            if let diskURL = DiskMediaManager.shared.loadAudioFromDisk(
                fileName: codeMessage,
                ext: candidate,
                pathName: .CHAT
            ) {
                return diskURL
            }
            if let diskURL = DiskMediaManager.shared.loadFileFromDisk(
                fileName: codeMessage,
                ext: candidate,
                pathName: .CHAT
            ) {
                return diskURL
            }
        }

        return nil
    }
}

// MARK: - Media Transfer Button
/// Wraps the original ExpandingRetryButton + CircularProgressView with
/// reactive state management via UploadViewModel Combine publishers.

public struct MediaTransferButton: View {
    @ObservedObject var uploadVM: FileUploadViewModel
    let messages: [MessageDataItem]
    let isDownload: Bool
    let translationService: (any TranslationServiceProtocol)?

    @State private var transferState: MediaTransferState = .idle
    @State private var hasCheckedCache = false

    /// The keys this control reports on, held steady for the whole operation.
    ///
    /// It cannot be recomputed from `pendingMessages` as the transfer runs: each
    /// item that lands leaves that list, so the set the progress is measured
    /// against would shrink under it and the bar would fall back to zero. Keys are
    /// only ever added while the control is on screen, never removed, so a
    /// finished item stays in the denominator as a finished item.
    @State private var trackedKeys: [String] = []

    /// The items this control is actually responsible for.
    ///
    /// A batch retry used to loop over every message it was given, so one failed
    /// photo in a group of five re-uploaded the four that had already gone —
    /// wasting the upload and rewriting four remote URLs that were already good.
    private var pendingMessages: [MessageDataItem] {
        let pending = messages.filter(\.mediaNeedsTransfer)
        return pending.isEmpty ? messages : pending
    }

    /// Only used for the kind-specific disk probes below, never for progress.
    private var message: MessageDataItem? { pendingMessages.first }

    /// How much of the batch each item accounts for.
    ///
    /// Bytes, so a 4 MB video does not advance the bar as fast as a 200 KB photo.
    /// Falls back to counting items equally when the sizes are unknown, which is
    /// the best available answer rather than a bar that never moves.
    private var weightsByKey: [String: Double] {
        let sizes = messages.map { ($0.codeMessage, Double($0.message.size ?? 0)) }
        // A single unknown size makes every byte-weighted total a lie — and worse,
        // gives that item a weight of zero, so finishing it would not move the bar
        // at all. One missing size drops the whole batch to counting items equally.
        let entries = sizes.allSatisfy { $0.1 > 0 } ? sizes : sizes.map { ($0.0, 1.0) }
        return Dictionary(entries, uniquingKeysWith: { first, _ in first })
    }

    /// Adds anything newly in need of transfer to the tracked set.
    ///
    /// Additive only — see `trackedKeys`.
    private func syncTrackedKeys() {
        let pending = pendingMessages.map(\.codeMessage).filter { !$0.isEmpty }
        let missing = pending.filter { !trackedKeys.contains($0) }
        guard !missing.isEmpty else { return }
        trackedKeys.append(contentsOf: missing)
    }

    private var isVideo: Bool {
        message?.typeMessage.isVideo == true
    }

    private var isDocument: Bool {
        message?.typeMessage == .DOCUMENT
    }

    /// Clears the persisted automatic-attempt count for a message the user retried.
    private let onRetryRequested: ((String) -> Void)?

    /// Fires when this control has nothing left to do — the media is here.
    ///
    /// The media viewer needs it: its page resolved a nil file URL when it opened
    /// and has no other way to learn that the file has since arrived.
    private let onTransferComplete: (() -> Void)?

    /// Passed to the shared executor, so a manual retry clears the pending flag and
    /// publishes exactly as the automatic path does.
    private let onUploadSuccess: ((String, String) -> Void)?
    private let onAutoTransferAttempt: ((String, Int) -> Void)?

    public init(
        uploadVM: FileUploadViewModel,
        messages: [MessageDataItem],
        isDownload: Bool,
        translationService: (any TranslationServiceProtocol)? = nil,
        onRetryRequested: ((String) -> Void)? = nil,
        onTransferComplete: (() -> Void)? = nil,
        onUploadSuccess: ((String, String) -> Void)? = nil,
        onAutoTransferAttempt: ((String, Int) -> Void)? = nil
    ) {
        self.uploadVM = uploadVM
        self.messages = messages
        self.isDownload = isDownload
        self.translationService = translationService
        self.onRetryRequested = onRetryRequested
        self.onTransferComplete = onTransferComplete
        self.onUploadSuccess = onUploadSuccess
        self.onAutoTransferAttempt = onAutoTransferAttempt
        if !isDownload, messages.first?.message.shouldRetry == true {
            _transferState = State(initialValue: .failure(error: "Upload failed"))
        }
    }

    public var body: some View {
        Group {
            switch transferState {
            case .idle, .failure:
                ExpandingRetryButton(
                    uploadVM: uploadVM,
                    messages: messages,
                    isDownload: isDownload,
                    translationService: translationService,
                    onRetryRequested: onRetryRequested,
                    onUploadSuccess: onUploadSuccess,
                    onAutoTransferAttempt: onAutoTransferAttempt
                )

            case .loading:
                CircularProgressView(
                    color: .white,
                    progress: 0.0,
                    repeatForever: true
                ) {
                    cancelTransfer()
                }

            case .transferring(let progress):
                CircularProgressView(
                    progress: progress,
                    repeatForever: false
                ) {
                    cancelTransfer()
                }

            case .success:
                EmptyView()
            }
        }
        .onAppear {
            syncTrackedKeys()

            guard isDownload, !hasCheckedCache else { return }
            hasCheckedCache = true
            guard let cacheKey = message?.codeMessage else { return }

            if isDocument {
                let ext = ChatMediaDiskResolver.documentExtension(
                    fileName: message?.message.fileName,
                    filePath: message?.message.file ?? message?.message.remoteUri,
                    mimeType: message?.message.mimeType
                )
                if !ext.isEmpty,
                   DiskMediaManager.shared.hasDiskFile(for: cacheKey, ext: ext, pathName: .CHAT) {
                    transferState = .success
                }
            } else if message?.typeMessage == .AUDIO || message?.typeMessage == .VOICE {
                let ext = ChatMediaDiskResolver.audioExtension(
                    fileName: message?.message.fileName,
                    filePath: message?.message.audio ?? message?.message.remoteUri,
                    mimeType: message?.message.mimeType
                )
                if DiskMediaManager.shared.hasDiskAudio(for: cacheKey, ext: ext, pathName: .CHAT) {
                    transferState = .success
                }
            } else {
                // Every tracked item, not just the first: one photo already on
                // disk never meant the batch was.
                let mediaType: MediaType = isVideo ? .video : .image
                let keys = trackedKeys
                var cachedCount = 0
                for key in keys {
                    uploadVM.checkIfCached(cachedkey: key, type: mediaType) { isCached in
                        if isCached { cachedCount += 1 }
                        if cachedCount == keys.count { transferState = .success }
                    }
                }
            }
        }
        // A recycled bubble keeps this view's `@State`, so a batch replaced by a
        // different one would otherwise report on the keys of its predecessor.
        .onChange(of: messages.map(\.codeMessage)) { _ in
            trackedKeys = []
            hasCheckedCache = false
            transferState = .idle
            syncTrackedKeys()
        }
        .onChange(of: transferState) { newState in
            if newState == .success { onTransferComplete?() }
        }
        .onReceive(statePublisher) { newState in
            if transferState != newState { transferState = newState }
        }
    }

    // MARK: - Cancel

    private func cancelTransfer() {
        for msg in pendingMessages {
            if isDownload {
                uploadVM.cancelDownload(for: msg.codeMessage)
            } else {
                uploadVM.cancelUpload(for: msg.codeMessage)
            }
        }
    }

    // MARK: - Reactive Bridge  UploadVM → MediaTransferState

    private var statePublisher: AnyPublisher<MediaTransferState, Never> {
        isDownload ? downloadStatePublisher : uploadStatePublisher
    }

    private var downloadStatePublisher: AnyPublisher<MediaTransferState, Never> {
        let keys = trackedKeys
        let weights = weightsByKey
        guard !keys.isEmpty else { return Just(.idle).eraseToAnyPublisher() }

        return uploadVM.$downloads
            .map { states in
                MediaBatchProgress.combine(keys.map { key in
                    (weights[key] ?? 1, MediaBatchProgress.sample(download: states[key]))
                })
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    private var uploadStatePublisher: AnyPublisher<MediaTransferState, Never> {
        let keys = trackedKeys
        let weights = weightsByKey
        guard !keys.isEmpty else { return Just(.idle).eraseToAnyPublisher() }

        return uploadVM.$uploads
            .map { states in
                MediaBatchProgress.combine(keys.map { key in
                    (weights[key] ?? 1, MediaBatchProgress.sample(upload: states[key]))
                })
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}

// MARK: - Batch progress

/// Folds a batch of transfers into the one state a single control shows.
///
/// Lives outside the view because it is arithmetic, not layout — and because a
/// batch reporting its progress wrongly is invisible in a screenshot and obvious
/// to anyone watching the bar.
enum MediaBatchProgress {

    /// One item's contribution, stripped of whether it was an upload or a download.
    enum Sample: Equatable {
        case idle
        case active(Double)
        case done
        case failed(String)
    }

    static func sample(upload state: UploadState?) -> Sample {
        switch state {
        case .uploading(let p): return .active(p)
        case .loading:          return .active(0)
        case .success:          return .done
        case .failure(let e):   return .failed(e)
        case .idle, .none:      return .idle
        }
    }

    static func sample(download state: DownloadState?) -> Sample {
        switch state {
        case .downloading(let p): return .active(p)
        case .success:            return .done
        case .failure(let e):     return .failed(e)
        case .idle, .none:        return .idle
        }
    }

    /// The control used to read one item's slot, so a group of five ran the ring
    /// from empty to full five times over. A batch is one operation to the person
    /// watching it, and one bar is what it should look like: bytes moved over bytes
    /// to move, across every item at once.
    static func combine(_ entries: [(weight: Double, sample: Sample)]) -> MediaTransferState {
        guard !entries.isEmpty else { return .idle }

        if entries.allSatisfy({ $0.sample == .done }) {
            return .success
        }

        let isActive = entries.contains { if case .active = $0.sample { return true }; return false }

        if isActive {
            let total = entries.reduce(0) { $0 + $1.weight }
            guard total > 0 else { return .loading }

            let moved = entries.reduce(0.0) { running, entry in
                switch entry.sample {
                case .done:           return running + entry.weight
                case .active(let p):  return running + entry.weight * p
                case .idle, .failed:  return running
                }
            }

            // Nothing measurable has moved yet — an indeterminate spinner is honest
            // here, where a bar pinned at zero reads as stuck.
            guard moved > 0 else { return .loading }
            return .transferring(progress: min(max(moved / total, 0), 1))
        }

        // Nothing running: a failure anywhere is what the batch has to report, since
        // it is the only state the user can act on.
        if let error = entries.compactMap({ entry -> String? in
            if case .failed(let e) = entry.sample { return e }
            return nil
        }).first {
            return .failure(error: error)
        }

        return .idle
    }
}

// MARK: - Original Expanding Retry Button (UI unchanged)

private struct ExpandingRetryButton: View {
    @State private var isExpanded = false
    @ObservedObject var uploadVM: FileUploadViewModel
    let messages: [MessageDataItem]
    let isDownload: Bool
    let translationService: (any TranslationServiceProtocol)?
    /// Lets the owner clear the persisted attempt count for a message the user has
    /// asked to retry. Optional so callers that do not persist need not care.
    var onRetryRequested: ((String) -> Void)? = nil

    /// Reports a finished upload, so the owner can clear the pending flag and
    /// publish. The retry path had no such callback and leaned on the view model's
    /// recovery hook instead — a second mechanism for the same job.
    var onUploadSuccess: ((String, String) -> Void)? = nil

    /// Reports the attempt total, so the allowance is persisted the same way it is
    /// on the automatic path.
    var onAutoTransferAttempt: ((String, Int) -> Void)? = nil

    /// Only what still has to move. Everything this button does — the size it
    /// quotes, the transfers it starts — is about these and nothing else.
    ///
    /// It used to loop over every message in the group, so one failed photo out of
    /// five re-uploaded the four that had already gone and overwrote four remote
    /// URLs that were already good.
    private var pendingMessages: [MessageDataItem] {
        let pending = messages.filter(\.mediaNeedsTransfer)
        return pending.isEmpty ? messages : pending
    }

    private var totalSize: String {
        var total = 0
        for msg in pendingMessages { total += msg.message.size ?? 0 }
        return total.formattedFileSize()
    }

    var body: some View {
        Button {
            // An explicit tap restores the automatic allowance for everything it
            // covers, so the retries that follow this one happen on their own again.
            for msg in pendingMessages {
                uploadVM.resetAutoTransferAttempts(key: msg.codeMessage)
                onRetryRequested?(msg.codeMessage)
            }

            // Both directions, every media kind, through the one shared entry
            // point — the same one the first send and the automatic retry use.
            //
            // This branch used to resolve disk URLs, build `UploadFile`s and pick
            // download calls itself, in parallel with two other copies of the same
            // logic in the bubbles. Keeping three in step was the problem.
            for msg in pendingMessages {
                InlineMediaTransferExecutor.startManualTransfer(
                    config: .forMessage(
                        msg,
                        onUploadSuccess: { remoteUrl in
                            onUploadSuccess?(msg.codeMessage, remoteUrl)
                        },
                        onAutoTransferAttempt: { attempts in
                            onAutoTransferAttempt?(msg.codeMessage, attempts)
                        }
                    ),
                    uploadVM: uploadVM
                )
            }

            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                if isExpanded {
                    if isDownload {
                        Image(systemName: "arrow.down.to.line")
                            .foregroundColor(Color.white)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                        Text(totalSize)
                            .font(.caption)
                            .foregroundColor(.white)
                            .opacity(0.8)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(Color.white)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                        Text(common("retry"))
                            .font(.caption)
                            .foregroundColor(.white)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }
            }
            .frame(height: 33)
            .padding(10)
            .background(Color.black.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 50, style: .continuous))
            .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    isExpanded = true
                }
            }
        }
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}
