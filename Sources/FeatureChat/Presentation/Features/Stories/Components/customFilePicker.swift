import SwiftUI
import UniformTypeIdentifiers


// MARK: - Document Picker (Fixed)
struct DocumentPickerView: UIViewControllerRepresentable {
    let allowMultiple: Bool
    let onFilesSelected: ([URL]) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let supportedTypes: [UTType] = [
            .pdf,
            .plainText,
            .rtf,
            .spreadsheet,
            .presentation,
            .archive,
            .image,
            .movie,
            .audio,
            UTType(filenameExtension: "doc") ?? .data,
            UTType(filenameExtension: "docx") ?? .data,
            UTType(filenameExtension: "xlsx") ?? .data,
            UTType(filenameExtension: "xls") ?? .data,
            UTType(filenameExtension: "ppt") ?? .data,
            UTType(filenameExtension: "pptx") ?? .data,
            UTType(filenameExtension: "csv") ?? .data,
            .data,
        ]

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes, asCopy: true)
        picker.allowsMultipleSelection = allowMultiple
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onFilesSelected: onFilesSelected)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFilesSelected: ([URL]) -> Void
        
        init(onFilesSelected: @escaping ([URL]) -> Void) {
            self.onFilesSelected = onFilesSelected
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onFilesSelected(urls)
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            // User cancelled - do nothing
        }
    }
}
