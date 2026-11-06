import SwiftUI
import PDFKit
import QuickLook
import WaanguSharedUI

struct BubbleDocumentView: View {
    let message: MessageDataItem
    @ObservedObject var uploadVM: FileUploadViewModel
    let isSelectionMode: Bool
    /// Held, not observed: the room view model is a service locator here, and
    /// subscribing every bubble to it re-rendered the whole timeline on any change.
    let chatVM: ChatRoomViewModel
    @State private var fileName = ""
    @State private var showPreview = false
    @Environment(\.colorScheme) private var colorScheme

    private var fileURL: URL? {
        ChatMediaDiskResolver.localDocumentURL(
            codeMessage: message.codeMessage,
            fileName: message.message.fileName,
            filePath: message.message.file ?? message.message.remoteUri,
            mimeType: message.message.mimeType
        )
    }

    private var localUploadURL: URL? {
        guard let url = fileURL, url.isFileURL else { return nil }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private var presentationKind: DocumentPresentationKind {
        DocumentPresentationKind.from(
            fileName: message.message.fileName ?? fileURL?.lastPathComponent,
            mimeType: message.message.mimeType
        )
    }

    private var transferConfig: InlineMediaTransferConfig {
        .document(
            message: message,
            localFileURL: localUploadURL,
            onUploadSuccess: { [codeMessage = message.codeMessage] remoteUrl in
                chatVM.clearPendingUpload(codeMessage: codeMessage, remoteUrl: remoteUrl)
            },
            onAutoTransferAttempt: { [codeMessage = message.codeMessage] attempts in
                chatVM.persistAutoTransferAttempts(codeMessage: codeMessage, attempts: attempts)
            }
        )
    }

    private var canShowRichPreview: Bool {
        presentationKind.usesRichPreview && fileURL != nil
    }

    var body: some View {
        HStack {
            if message.direction == .sent {
                // A failed transfer is still pending, so the second half of this
                // test used to keep the error marker off the one message it is for.
                if message.message.shouldRetry {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.red)
                        .font(.headline)
                } else {
                    VStack(spacing: 8) {
                        bubbleForwardButton(message: message, chatVM: chatVM, isSelectionMode: isSelectionMode)
                    }
                }
            }

            if message.direction == .sent {
                Spacer()
            }

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    forwardedIndicator(
                        for: message,
                        forwardedLabel: chatVM.translationService?.resolve(
                            key: ChatTranslationKeys.FORWARDED,
                            module: ChatTranslationKeys.MODULE
                        ).value ?? "Forwarded"
                    )

                    ZStack {
                        if canShowRichPreview, let url = fileURL {
                            pdfPreviewSection(url: url)
                        } else {
                            compactFileRow(url: fileURL)
                        }

                        // Same transfer button as voice: only visible while idle/failed/transferring.
                        if canShowRichPreview {
                            InlineMediaTransferControl(
                                uploadVM: uploadVM,
                                config: transferConfig,
                                isSelectionMode: isSelectionMode,
                                translator: chatVM.translationService,
                                readyContent: { EmptyView() }
                            )
                        }
                    }

                }
                .overlay(alignment: .bottomTrailing) {
                    BubbleMetaOverlay(message: message, style: .bubble(colorScheme: colorScheme), translationService: chatVM.translationService)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                }
                .background(message.backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .applyStrokeOnBubbleView()
                .applyTailView(message.direction)
                .shadow(color: Color(.systemGray3).opacity(0.1), radius: 5, x: 0, y: 20)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(maxWidth: canShowRichPreview ? UIScreen.main.bounds.width * 0.75 : 300, alignment: message.alignment)
                .frame(maxWidth: .infinity, alignment: message.alignment)
                .onTapGesture {
                    guard !isSelectionMode else { return }
                    if fileURL != nil {
                        showPreview = true
                    }
                }
                .allowsHitTesting(!isSelectionMode)
                .chatAppearanceSheet(isPresented: $showPreview) {
                    if let url = fileURL {
                        DocumentPreviewSheet(url: url)
                    }
                }
            }

            if message.direction == .received {
                // A failed transfer is still pending, so the second half of this
                // test used to keep the error marker off the one message it is for.
                if message.message.shouldRetry {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.red)
                        .font(.headline)
                } else {
                    VStack(spacing: 8) {
                        bubbleForwardButton(message: message, chatVM: chatVM, isSelectionMode: isSelectionMode)
                    }
                }
            }
        }
        .padding(.leading, message.direction == .received ? 10 : 60)
        .padding(.trailing, message.direction == .received ? 60 : 10)
        .id(message.id)
        .onAppear {
            fileName = message.message.fileName
                ?? fileURL?.lastPathComponent.removingPercentEncoding
                ?? "Document"

            InlineMediaTransferExecutor.triggerAutoUploadIfNeeded(
                config: transferConfig,
                uploadVM: uploadVM
            )
        }
    }

    // MARK: - Compact file row (WhatsApp-style)

    @ViewBuilder
    private func compactFileRow(url: URL?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            InlineMediaTransferControl(
                uploadVM: uploadVM,
                config: transferConfig,
                isSelectionMode: isSelectionMode,
                translator: chatVM.translationService,
                readyContent: {
                    fileTypeIcon
                }
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(fileName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ChatBubbleStyle.foreground(for: colorScheme))
                    .lineLimit(2)
                    .truncationMode(.middle)

                Text(
                    presentationKind.metadataLine(
                        fileName: message.message.fileName,
                        fileURL: url,
                        sizeBytes: message.message.size
                    )
                )
                .font(.caption)
                .foregroundStyle(ChatBubbleStyle.secondaryForeground(for: colorScheme))
                .padding(.trailing, 72)
                .padding(.bottom, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fileTypeIcon: some View {
        Image(systemName: presentationKind.systemImageName)
            .font(.system(size: 26))
            .foregroundColor(presentationKind.iconColor)
            .frame(width: 34, height: 40, alignment: .center)
    }

    // MARK: - PDF Preview

    @ViewBuilder
    private func pdfPreviewSection(url: URL) -> some View {
        ZStack(alignment: .bottom) {
            PDFFirstPageView(url: url)
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .clipped()

            pdfInfoBar(url: url)
        }
        .background(Color(UIColor.systemGray6))
        .cornerRadius(8)
        .padding(8)
    }

    @ViewBuilder
    private func pdfInfoBar(url: URL) -> some View {
        HStack {
            Spacer().frame(width: 10)
            Image(systemName: presentationKind.systemImageName)
                .resizable()
                .scaledToFit()
                .frame(width: 20)
                .foregroundColor(presentationKind.iconColor)

            VStack(alignment: .leading) {
                Text(fileName)
                    .bold()
                    .font(.subheadline)
                    .foregroundStyle(ChatBubbleStyle.foreground(for: colorScheme))
                    .lineLimit(2)
                    .truncationMode(.tail)
                Text(
                    presentationKind.metadataLine(
                        fileName: message.message.fileName,
                        fileURL: url,
                        sizeBytes: message.message.size
                    )
                )
                .foregroundStyle(ChatBubbleStyle.secondaryForeground(for: colorScheme))
                .font(.caption)
            }
            .padding(.vertical, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(message.backgroundColor.opacity(0.9))
    }

    // MARK: - Helpers
}

// MARK: - PDF First Page Renderer

struct PDFFirstPageView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = PDFDocument(url: url)
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.isUserInteractionEnabled = false
        pdfView.backgroundColor = .systemGray6
        if let firstPage = pdfView.document?.page(at: 0) {
            pdfView.go(to: firstPage)
        }
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}

// MARK: - Document Preview via QuickLook

struct DocumentPreviewSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
