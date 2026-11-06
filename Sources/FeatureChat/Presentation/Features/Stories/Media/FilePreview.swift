
import SwiftUI
import UniformTypeIdentifiers
import PDFKit
import QuickLookThumbnailing
import AVKit
import Foundation
import QuickLook
import WaanguCoreKit

// MARK: - 1. File Picker (supports all file types)
struct UniversalFilePicker: UIViewControllerRepresentable {
    var onPicked: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.item], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPicked: (URL) -> Void
        
        init(onPicked: @escaping (URL) -> Void) {
            self.onPicked = onPicked
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPicked(url)
        }
    }
}



@available(iOS 16.0, *)
struct WhatsAppFilePreview: View {
//    let pdfURL: URL
    let fileURL: URL
    @Binding var messageText: String
    @Environment(\.dismiss) private var dismiss
    let statusStore:StoriesViewModel
    @Binding var pagesCount : Int
    let translationService: (any TranslationServiceProtocol)?

    init(
        fileURL: URL,
        messageText: Binding<String>,
        statusStore: StoriesViewModel,
        pagesCount: Binding<Int>,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        self.fileURL = fileURL
        self._messageText = messageText
        self.statusStore = statusStore
        self._pagesCount = pagesCount
        self.translationService = translationService
    }

    var documentName: String {
//        pdfURL.lastPathComponent
        fileURL.lastPathComponent.removingPercentEncoding ?? ""
        
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(documentName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text("\(fileURL.pathExtension.uppercased())")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
                
//                Button(action: {}) {
//                    Image(systemName: "square.and.arrow.up")
//                        .font(.title3)
//                        .foregroundColor(.white)
//                }
            }
            .padding(.horizontal,12)
            .padding(.vertical, 12)
            .background(Color(hex: "075E54")) // WhatsApp green
            
            // Your existing PDF Preview code
//            PDFPreview(pdfURL: pdfURL)
            VStack {
                if fileURL.pathExtension.lowercased() == "pdf" {
    //                PDFPreview(pdfURL: fileURL)
                    PDFPreview(
                        pdfURL: fileURL,
                        pagesCount: $pagesCount,
                        translationService: translationService
                    )
                } else if ["png", "jpg", "jpeg", "heic"].contains(fileURL.pathExtension.lowercased()) {
                    ImagePreview(imageURL: fileURL, translationService: translationService)
                } else if ["mp4", "mov", "m4v"].contains(fileURL.pathExtension.lowercased()) {
                    VideoPreview(videoURL: fileURL)
                } else {
                    DefaultFileView(fileURL: fileURL)
                }
            }.frame(maxWidth: .infinity,maxHeight: .infinity)
            
            // Message Input Area
            HStack(alignment: .bottom, spacing: 8) {
                HStack(spacing: 8) {
                    Button(action: {}) {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 24))
                            .foregroundColor(.gray)
                    }
                    
                    if #available(iOS 16.0, *) {
                        TextField(t(ChatTranslationKeys.STORIES_FILE_ADD_CAPTION), text: $messageText, axis: .vertical)
                            .font(.system(size: 16))
                            .lineLimit(1...5)
                            .padding(.vertical, 8)
                    } else {
                        // Fallback on earlier versions
                        
                    }
                    
//                    if !messageText.isEmpty {
//                        Button(action: { messageText = "" }) {
//                            Image(systemName: "xmark.circle.fill")
//                                .font(.system(size: 18))
//                                .foregroundColor(.gray)
//                        }
//                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white)
                .cornerRadius(20)
                
                Button(action: {
                    // Send action
                   
                    statusStore.isDocSent = !statusStore.isDocSent
                    debugLog("doc State \(statusStore.isDocSent)")
                    dismiss()
                    
                 
                    
                }) {
                    Circle()
                        .fill(Color(hex: "25D366")) // WhatsApp green
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                        )
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color(UIColor.systemGray6))
        }.padding(0)
        .navigationBarHidden(true)
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}
// MARK: - 3a. PDF Viewer
struct PDFPreview: View {
    let pdfURL: URL
    @Binding var pagesCount : Int
    let translationService: (any TranslationServiceProtocol)?

    init(
        pdfURL: URL,
        pagesCount: Binding<Int>,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        self.pdfURL = pdfURL
        self._pagesCount = pagesCount
        self.translationService = translationService
    }

    var body: some View {
        if let document = PDFDocument(url: pdfURL) {
            VStack {
                PDFKitView(document: document,onPageCount: {count in
                    debugLog("pages from files \(count)")
                    pagesCount = count
                })
            }.frame(maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/,maxHeight: .infinity)
        } else {
            Text(t(ChatTranslationKeys.STORIES_FILE_PDF_ERROR))
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    let onPageCount: ((Int) -> Void)?
    
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.backgroundColor = .systemGray6
        onPageCount?(document.pageCount)
        return pdfView
    }
    
    func updateUIView(_ uiView: PDFView, context: Context) {}
}

// MARK: - 3b. Image Viewer
struct ImagePreview: View {
    let imageURL: URL
    let translationService: (any TranslationServiceProtocol)?

    init(imageURL: URL, translationService: (any TranslationServiceProtocol)? = nil) {
        self.imageURL = imageURL
        self.translationService = translationService
    }

    var body: some View {
        if let data = try? Data(contentsOf: imageURL),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .background(Color.black.opacity(0.1))
                .edgesIgnoringSafeArea(.bottom)
        } else {
            Text(t(ChatTranslationKeys.STORIES_FILE_IMAGE_ERROR))
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

// MARK: - 3c. Video Viewer
struct VideoPreview: View {
    let videoURL: URL
    
    var body: some View {
        VideoPlayer(player: AVPlayer(url: videoURL))
            .edgesIgnoringSafeArea(.bottom)
    }
}



struct FileThumbnailView: View {
    let fileURL: URL
    let size: CGSize
    
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .cornerRadius(8)
            } else {
                ProgressView()
                    .frame(width: size.width, height: size.height)
            }
        }
        .onAppear {
            generateThumbnail()
        }
    }

    private func generateThumbnail() {
        let scale = UIScreen.main.scale
        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: size,
            scale: scale,
            representationTypes: .all
        )
        
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, error in
            DispatchQueue.main.async {
                if let thumbnail = thumbnail {
                    self.image = thumbnail.uiImage
                } else {
                    debugLog("❌ Thumbnail error: \(error?.localizedDescription ?? "unknown error")")
                    self.image = UIImage(systemName: "doc.fill")
                }
            }
        }
    }
}

// MARK: - 3d. Default (unsupported) File View


struct DefaultFileView: UIViewControllerRepresentable {
    let fileURL: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(fileURL: fileURL)
    }

    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let fileURL: URL

        init(fileURL: URL) {
            self.fileURL = fileURL
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            fileURL as NSURL
        }
    }
}

// MARK: - 4. Main Content View
@available(iOS 16.0, *)
struct FilePreview: View {
    @State private var selectedFileURL: URL?
    @State private var showFilePicker = false
    @State private var goNext = false
    @State private var messageText = ""
    let statusStore:StoriesViewModel
    @State private var pagesCount : Int = 0
    @State private var sizeInBytes = ""
    @State private var fileName = ""
    @State private var description: String = ""
    let translationService: (any TranslationServiceProtocol)?

    init(
        statusStore: StoriesViewModel,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        self.statusStore = statusStore
        self.translationService = translationService
    }


    func getFileSizeString(for fileURL: URL) -> String {
        // Try to get file size in bytes
        var sizeInBytes: Int64 = 0
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let fileSize = attributes[.size] as? NSNumber {
                sizeInBytes = fileSize.int64Value
            }
        } catch {
            debugLog("❌ Error getting file size: \(error)")
            return t(ChatTranslationKeys.STORIES_FILE_UNKNOWN_SIZE)
        }

        // Convert to KB, MB, GB as needed
        let kb = Double(sizeInBytes) / 1024
        let mb = kb / 1024
        let gb = mb / 1024

        if gb >= 1 {
            return String(format: "%.2f GB", gb)
        } else if mb >= 1 {
            return String(format: "%.2f MB", mb)
        } else {
            return String(format: "%.2f KB", kb)
        }
    }

    
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let fileURL = selectedFileURL {
                    NavigationLink(destination: WhatsAppFilePreview(fileURL: fileURL,messageText: $description, statusStore: statusStore,pagesCount: $pagesCount, translationService: translationService),isActive: $goNext){
                        EmptyView()
                    }
                }
//
                    VStack(spacing: 16) {
                        Spacer()
                        if statusStore.isDocSent  {
                            if let fileURL = selectedFileURL {
                                VStack(alignment: .leading){
                                    VStack(alignment:.leading){
                                        GeometryReader { geometry in
                                            ZStack{
                                                
                                          
    //                                            Spacer().frame(width: /*@START_MENU_TOKEN@*/100/*@END_MENU_TOKEN@*/,height: 230).background(.green)
                                                FileThumbnailView(fileURL: fileURL, size: CGSize(width: geometry.size.width, height: 360)).zIndex(0)
                                                
                                                VStack(alignment:.leading){
                                                    Spacer()
                                                    HStack{
                                                        Spacer().frame(width: 10)
                                                        Image(systemName: "doc.fill").resizable()
                                                            .scaledToFit()
                                                            .frame(width: 20).foregroundColor(.white)
                                                        VStack(alignment: .leading){
                                                            Text("\(fileName)").bold().font(.subheadline).foregroundStyle(.white).lineLimit(2)               // allow 2 lines max
                                                                .truncationMode(.tail)
                                                         
                                                            Text("\(t(ChatTranslationKeys.STORIES_FILE_PAGES, args: ["\(pagesCount)"])) · \((fileName.split(separator: ".").last.map { String($0).uppercased() } ?? "")) · \(sizeInBytes)")
                                                                .foregroundStyle(.white.opacity(0.8))
                                                                .font(.caption)
                                                        }.padding(.vertical,8)
                                                        Spacer()
                                                    }.frame(maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/).background(.green.opacity(0.9))
                                                  
                                                }.frame(width: geometry.size.width , height: geometry.size.height)
                                                
                                              
    //
                                            }.frame(maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/,maxHeight: geometry.size.height)
                                        }
                                       
                                     
                                                                                     
                                                                                 }.frame(maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/,maxHeight: 200).background(.black.opacity(0.2)).cornerRadius(8).padding(.horizontal,8).padding(.vertical,8).clipped()
                                                                                 Spacer()
                                    Text("\(description)").padding(.leading,12).foregroundColor(.white)
                                                                                 Spacer()
                                                                                 
                                                                             }.frame(maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/ ,maxHeight: 200).background(.green).cornerRadius(12).padding(.leading,100)
                            }
                            
                           
                        }
                  
                        HStack(alignment: .bottom, spacing: 8) {
                            HStack(spacing: 8) {
//                                Button(action: {}) {
//                                    Image(systemName: "face.smiling")
//                                        .font(.system(size: 24))
//                                        .foregroundColor(.gray)
//                                }
                                EmojiPicker(selectedIcon: $messageText, translationService: translationService)
                                    .font(.system(size:24))
                                    .foregroundColor(.gray)
                                
                                if #available(iOS 16.0, *) {
                                    TextField(t(ChatTranslationKeys.STORIES_TYPE_HERE), text: $messageText, axis: .vertical)
                                        .font(.system(size: 16))
                                        .lineLimit(1...5)
                                        .padding(.vertical, 8)
                                } else {
                                    // Fallback on earlier versions
                                }
                                
                                Image(systemName: "doc").resizable().scaledToFit().frame(width: 20).foregroundColor(.gray).onTapGesture {
                                    debugLog("hello gesture")
                                    showFilePicker = true
                                   statusStore.isDocSent = false
                                }
                                                        }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.gray.opacity(0.3))
                            .cornerRadius(20)
                            
                            Button(action: {
                                // Send action
                                
                                debugLog("sent one")
                            }) {
                                Circle()
                                    .fill(Color(hex: "25D366")) // WhatsApp green
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Image(systemName: "paperplane.fill")
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundColor(.white)
                                    )
                            }
                        }
                        .padding(.vertical, 8)
//                        .padding(.horizontal, 12)
                        .background(Color(UIColor.systemGray6))
//
                    }.padding(.horizontal,12)
                }
        
            .chatAppearanceSheet(isPresented: $showFilePicker) {
                UniversalFilePicker { url in
                    
                    selectedFileURL = url
                    goNext = true
                    sizeInBytes = getFileSizeString(for: url)
                    if let filename = url.lastPathComponent.removingPercentEncoding {
                        debugLog("File name: \(filename)")
                        fileName = filename
                    }
                }
            }
//            .navigationTitle("All Files Viewer")
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}
