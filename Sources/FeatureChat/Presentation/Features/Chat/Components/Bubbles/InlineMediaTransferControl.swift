import Combine
import WaanguCoreKit
import WaanguSharedUI
import SwiftUI

// MARK: - Phase

enum InlineMediaTransferPhase: Equatable {
    case idle
    case transferring(progress: Double)
    case failed
    case ready
}

// MARK: - Config

enum InlineMediaTransferMediaKind {
    case voice
    case document
    case image
    case video
}

struct InlineMediaTransferConfig {
    let message: MessageDataItem
    let mediaKind: InlineMediaTransferMediaKind
    let localFileURL: URL?
    let onUploadSuccess: ((String) -> Void)?
    /// Reports the new automatic-attempt total so the owner can persist it onto the
    /// message, which is what makes the cap outlive the session.
    var onAutoTransferAttempt: ((Int) -> Void)? = nil

    /// Whether moving this media means sending it rather than fetching it.
    ///
    /// Read from the message's own pending flag, not from `direction`. A voice note
    /// or document sent from the web or a second device on this account arrives
    /// with our own `senderId`, so `direction == .sent` — it used to take the
    /// upload branch, find no local file, and settle on `.ready` for a file this
    /// device has never held.
    ///
    /// It also covers our own send whose cached copy has since been evicted: not
    /// pending any more, not on disk, so it has to come back down.
    var isUpload: Bool { message.message.shouldUploadDownload }
    var uploadKey: String { message.codeMessage }
    var downloadKey: String { message.codeMessage }

    /// The server's copy of this media, or empty when there is no address at all.
    ///
    /// Prefers the resolved remote address — `audio` and `file` can each hold a
    /// local path for something this device queued — but falls back to the raw
    /// fields rather than resolving to nothing, so an address this app does not
    /// recognise still gets its attempt.
    var remoteMediaURL: String {
        if let resolved = message.remoteMediaURLString { return resolved }
        switch mediaKind {
        case .voice:    return message.message.audio ?? message.message.remoteUri ?? ""
        case .document: return message.message.file ?? message.message.remoteUri ?? ""
        case .image:    return message.message.image ?? message.message.remoteUri ?? ""
        case .video:    return message.message.video ?? message.message.remoteUri ?? ""
        }
    }

    static func voice(
        message: MessageDataItem,
        localFileURL: URL?,
        onUploadSuccess: ((String) -> Void)? = nil,
        onAutoTransferAttempt: ((Int) -> Void)? = nil
    ) -> InlineMediaTransferConfig {
        InlineMediaTransferConfig(
            message: message,
            mediaKind: .voice,
            localFileURL: localFileURL,
            onUploadSuccess: onUploadSuccess,
            onAutoTransferAttempt: onAutoTransferAttempt
        )
    }

    static func document(
        message: MessageDataItem,
        localFileURL: URL?,
        onUploadSuccess: ((String) -> Void)? = nil,
        onAutoTransferAttempt: ((Int) -> Void)? = nil
    ) -> InlineMediaTransferConfig {
        InlineMediaTransferConfig(
            message: message,
            mediaKind: .document,
            localFileURL: localFileURL,
            onUploadSuccess: onUploadSuccess,
            onAutoTransferAttempt: onAutoTransferAttempt
        )
    }

    /// A photo or a video.
    ///
    /// The kind and the local file both follow the message, so no caller has to
    /// say which it is holding or work out where it lives. This is what lets the
    /// first send, the automatic retry and the manual retry ask for the same thing
    /// in the same words.
    static func media(
        message: MessageDataItem,
        onUploadSuccess: ((String) -> Void)? = nil,
        onAutoTransferAttempt: ((Int) -> Void)? = nil
    ) -> InlineMediaTransferConfig {
        InlineMediaTransferConfig(
            message: message,
            mediaKind: message.typeMessage.isVideo ? .video : .image,
            localFileURL: ChatMediaDiskResolver.localMediaURL(for: message),
            onUploadSuccess: onUploadSuccess,
            onAutoTransferAttempt: onAutoTransferAttempt
        )
    }

    /// The config for a message, whatever kind of media it carries.
    ///
    /// One entry point for a caller holding an arbitrary message — a batch retry
    /// does not want to switch on type to build a config just so the executor can
    /// switch on it again.
    static func forMessage(
        _ message: MessageDataItem,
        onUploadSuccess: ((String) -> Void)? = nil,
        onAutoTransferAttempt: ((Int) -> Void)? = nil
    ) -> InlineMediaTransferConfig {
        switch message.typeMessage {
        case .DOCUMENT:
            return .document(
                message: message,
                localFileURL: ChatMediaDiskResolver.localDocumentURL(
                    codeMessage: message.codeMessage,
                    fileName: message.message.fileName,
                    filePath: message.message.file ?? message.message.remoteUri,
                    mimeType: message.message.mimeType
                ),
                onUploadSuccess: onUploadSuccess,
                onAutoTransferAttempt: onAutoTransferAttempt
            )
        case .AUDIO, .VOICE:
            return .voice(
                message: message,
                localFileURL: ChatMediaDiskResolver.localAudioURL(
                    codeMessage: message.codeMessage,
                    fileName: message.message.fileName,
                    filePath: message.message.audio ?? message.message.remoteUri,
                    mimeType: message.message.mimeType
                ),
                onUploadSuccess: onUploadSuccess,
                onAutoTransferAttempt: onAutoTransferAttempt
            )
        default:
            return .media(
                message: message,
                onUploadSuccess: onUploadSuccess,
                onAutoTransferAttempt: onAutoTransferAttempt
            )
        }
    }
}

enum InlineMediaTransferStateResolver {
    static func phase(
        config: InlineMediaTransferConfig,
        uploadState: UploadState?,
        downloadState: DownloadState?
    ) -> InlineMediaTransferPhase {
        let message = config.message

        if config.isUpload {
            // What is happening right now outranks what was recorded about the last
            // attempt.
            switch uploadState {
            case .loading:                 return .transferring(progress: 0)
            case .uploading(let progress): return .transferring(progress: progress)
            case .success:                 return .ready
            case .failure:                 return .failed
            case .idle, .none:             break
            }

            // Nothing live — fall back to what the message itself remembers.
            //
            // A failed upload is both still pending and failed. The previous shape
            // tested those two flags as though they were exclusive, so once
            // `shouldRetry` could actually be true a failed upload matched neither
            // branch and fell through to `.ready` — no control at all on the one
            // case that needs one.
            //
            // Reaching here means the message is still pending by definition, so
            // the only question left is whether the last attempt failed.
            return message.message.shouldRetry ? .failed : .idle
        }

        switch downloadState {
        case .downloading(let progress): return .transferring(progress: progress)
        case .success:                   return .ready
        case .failure:                   return .failed
        case .idle, .none:
            if config.localFileURL != nil { return .ready }
            return message.message.shouldRetry ? .failed : .idle
        }
    }

    static func needsTransferUI(phase: InlineMediaTransferPhase, config: InlineMediaTransferConfig) -> Bool {
        switch phase {
        case .ready:
            return false
        case .idle, .failed, .transferring:
            if config.isUpload {
                return messageNeedsOutgoingTransfer(config.message)
            }
            return config.localFileURL == nil
        }
    }

    static func messageNeedsOutgoingTransfer(_ message: MessageDataItem) -> Bool {
        message.message.shouldUploadDownload == true || message.message.shouldRetry == true
    }

    static func messageNeedsIncomingTransfer(_ message: MessageDataItem, hasLocalFile: Bool) -> Bool {
        !hasLocalFile
    }
}

// MARK: - Executor

enum InlineMediaTransferExecutor {
    @MainActor
    static func startTransfer(config: InlineMediaTransferConfig, uploadVM: FileUploadViewModel) {
        let message = config.message

        if config.isUpload {
            // Reported rather than returned from quietly. This is the one place an
            // upload can fail to even begin, and a manual retry that hits it used to
            // do nothing at all — no attempt, no failure, no explanation.
            guard let resolvedURL = config.localFileURL,
                  let fileName = message.message.fileName,
                  let mimeType = message.message.mimeType else {
                uploadVM.markUploadFailed(
                    trackingKey: message.codeMessage,
                    error: config.localFileURL == nil ? ChatErrorStrings.localFileNotFound : ChatErrorStrings.fileDetailsMissing
                )
                return
            }

            Task {
                await uploadVM.upload(
                    file: UploadFile(
                        trackingKey: message.codeMessage,
                        fileURL: resolvedURL.absoluteString,
                        filename: fileName,
                        mimeType: mimeType,
                        receiverID: message.receiverId,
                        sizeBytes: message.message.size
                    ),
                    onSuccess: { remoteUrl in
                        config.onUploadSuccess?(remoteUrl)
                    }
                )
            }
            return
        }

        // Passed through even when empty: the downloader reports "Missing download
        // URL" as a failure the user can see and retry, where returning early here
        // would make the tap do nothing at all.
        let remoteURL = config.remoteMediaURL

        switch config.mediaKind {
        case .voice:
            let ext = ChatMediaDiskResolver.audioExtension(
                fileName: message.message.fileName,
                filePath: message.message.audio ?? message.message.remoteUri,
                mimeType: message.message.mimeType
            )
            uploadVM.downloadAudio(
                urlString: remoteURL,
                cacheKey: message.codeMessage,
                fileExtension: ext
            )
        case .document:
            let ext = ChatMediaDiskResolver.documentExtension(
                fileName: message.message.fileName,
                filePath: message.message.file ?? message.message.remoteUri,
                mimeType: message.message.mimeType
            )
            uploadVM.downloadDocument(
                urlString: remoteURL,
                cacheKey: message.codeMessage,
                fileExtension: ext
            )
        case .image:
            uploadVM.downloadImage(urlString: remoteURL, cacheKey: message.codeMessage)
        case .video:
            uploadVM.downloadVideo(urlString: remoteURL, cacheKey: message.codeMessage)
        }
    }

    @MainActor
    static func cancelTransfer(config: InlineMediaTransferConfig, uploadVM: FileUploadViewModel) {
        if config.isUpload {
            uploadVM.cancelUpload(for: config.uploadKey)
        } else {
            uploadVM.cancelDownload(for: config.downloadKey)
        }
    }

    @MainActor
    static func triggerAutoUploadIfNeeded(
        config: InlineMediaTransferConfig,
        uploadVM: FileUploadViewModel
    ) {
        let onAttempt = config.onAutoTransferAttempt
        guard config.isUpload else { return }
        guard config.message.message.shouldUploadDownload == true,
              config.message.message.shouldRetry == false,
              config.message.message.mimeType != nil else { return }

        let trackingKey = config.message.codeMessage
        let existingState = uploadVM.uploads[trackingKey]
        switch existingState {
        case .success, .uploading, .loading:
            return
        default:
            break
        }

        // A previous attempt failed, and `.failure` falls through the switch above
        // — so without this the upload was retried on every appearance of the row,
        // for as long as the message stayed in the thread.
        let persisted = config.message.message.autoTransferAttempts
        guard uploadVM.canAutoTransfer(key: trackingKey, persistedAttempts: persisted) else { return }

        guard config.localFileURL != nil else {
            if let fileName = config.message.message.fileName, !fileName.isEmpty {
                uploadVM.markUploadFailed(trackingKey: trackingKey, error: "Local file not found")
            }
            // Counted: a file that is not on disk will not appear on its own, and
            // this is the case that spun hardest — a `Data(contentsOf:)` and a
            // failed request on every scroll past.
            onAttempt?(uploadVM.recordAutoTransferAttempt(key: trackingKey, persistedAttempts: persisted))
            return
        }

        onAttempt?(uploadVM.recordAutoTransferAttempt(key: trackingKey, persistedAttempts: persisted))
        startTransfer(config: config, uploadVM: uploadVM)
    }

    @MainActor
    static func triggerAutoDownloadIfNeeded(
        config: InlineMediaTransferConfig,
        uploadVM: FileUploadViewModel
    ) {
        let onAttempt = config.onAutoTransferAttempt
        guard !config.isUpload else { return }
        guard config.localFileURL == nil else { return }
        guard !config.remoteMediaURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if let existingState = uploadVM.downloads[config.downloadKey] {
            switch existingState {
            case .success, .downloading:
                return
            case .failure, .idle:
                // A failed download used to stop dead here and wait for a tap.
                // It now gets the same allowance as an upload, since the usual
                // reason is a connection that is about to come back.
                break
            }
        }

        let persisted = config.message.message.autoTransferAttempts
        guard uploadVM.canAutoTransfer(key: config.downloadKey, persistedAttempts: persisted) else { return }

        onAttempt?(uploadVM.recordAutoTransferAttempt(key: config.downloadKey, persistedAttempts: persisted))
        startTransfer(config: config, uploadVM: uploadVM)
    }

    /// Starts a transfer the user asked for, restoring the automatic allowance.
    ///
    /// An explicit tap always proceeds, whatever the counter says, and clears it so
    /// the retries that follow are automatic again.
    @MainActor
    static func startManualTransfer(
        config: InlineMediaTransferConfig,
        uploadVM: FileUploadViewModel
    ) {
        let key = config.isUpload ? config.message.codeMessage : config.downloadKey
        uploadVM.resetAutoTransferAttempts(key: key)
        config.onAutoTransferAttempt?(0)
        startTransfer(config: config, uploadVM: uploadVM)
    }
}

// MARK: - Control

struct InlineMediaTransferControl<ReadyContent: View>: View {
    @ObservedObject var uploadVM: FileUploadViewModel
    let config: InlineMediaTransferConfig
    let isSelectionMode: Bool
    var controlSize: CGFloat = 40
    var progressControlSize: CGFloat = 56
    /// For the spoken names of the transfer controls; without one they fall back to English.
    var translator: (any TranslationServiceProtocol)? = nil
    @ViewBuilder let readyContent: () -> ReadyContent

    @State private var uploadState: UploadState?
    @State private var downloadState: DownloadState?
    @State private var hasCheckedCache = false

    private var phase: InlineMediaTransferPhase {
        InlineMediaTransferStateResolver.phase(
            config: config,
            uploadState: uploadState,
            downloadState: downloadState
        )
    }

    private func name(_ key: String, fallback: String) -> String {
        translator?.resolve(key: key, module: ChatTranslationKeys.MODULE).value ?? fallback
    }

    var body: some View {
        Group {
            switch phase {
            case .idle, .failed:
                Button(action: { InlineMediaTransferExecutor.startManualTransfer(config: config, uploadVM: uploadVM) }) {
                    Image(systemName: phase == .failed ? "arrow.clockwise" : (config.isUpload ? "arrow.up" : "arrow.down"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Color.orange.opacity(0.7))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .frame(width: controlSize, height: controlSize)
                .allowsHitTesting(!isSelectionMode)
                .accessibilityLabel(
                    phase == .failed
                        ? name(ChatTranslationKeys.CHAT_A11Y_RETRY_TRANSFER, fallback: "Retry transfer")
                        : (config.isUpload
                            ? name(ChatTranslationKeys.CHAT_A11Y_UPLOAD, fallback: "Upload")
                            : name(ChatTranslationKeys.CHAT_A11Y_DOWNLOAD, fallback: "Download"))
                )

            case .transferring(let progress):
                // The waiting spinner drawn at the size of the progress ring that
                // replaces it (`CircularProgressView` insets its ring to 23 pt).
                // Left at its 40 pt default, the circle shrank as soon as the
                // first byte was reported.
                CircularProgressView(
                    size: 23,
                    color: AppColors.primary,
                    progress: progress,
                    repeatForever: progress == 0,
                    showBackground: false,
                    cancelIcon: "xmark"
                ) {
                    InlineMediaTransferExecutor.cancelTransfer(config: config, uploadVM: uploadVM)
                }
                .frame(width: progressControlSize, height: progressControlSize)
                .allowsHitTesting(!isSelectionMode)
                // The ring and its cancel glyph are one control: named, with the progress as its
                // value, and cancelled by the standard activation.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(name(ChatTranslationKeys.CHAT_A11Y_CANCEL_TRANSFER, fallback: "Cancel transfer"))
                .accessibilityValue(progress > 0 ? "\(Int((progress * 100).rounded()))%" : "")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    InlineMediaTransferExecutor.cancelTransfer(config: config, uploadVM: uploadVM)
                }

            case .ready:
                readyContent()
            }
        }
        .onAppear {
            guard !config.isUpload, !hasCheckedCache else { return }
            hasCheckedCache = true
            if config.localFileURL != nil {
                downloadState = .success
            } else {
                InlineMediaTransferExecutor.triggerAutoDownloadIfNeeded(
                    config: config,
                    uploadVM: uploadVM
                )
            }
        }
        .onReceive(uploadVM.downloadPublisher(for: config.downloadKey)) { state in
            if downloadState != state { downloadState = state }
        }
        .onReceive(uploadVM.uploadPublisher(for: config.uploadKey)) { state in
            if uploadState != state { uploadState = state }
        }
    }
}
