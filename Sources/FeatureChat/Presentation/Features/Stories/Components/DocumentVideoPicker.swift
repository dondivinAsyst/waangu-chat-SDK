import SwiftUI
import UniformTypeIdentifiers
import UIKit
import WaanguCoreKit

struct DocumentMediaPicker: UIViewControllerRepresentable {
    @Binding var selectedURLs: [URL] // Can store multiple selected files
    var allowMultiple: Bool = false
    var allowedTypes: [UTType] = [.image, .movie, .video] // default to images & videos

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedTypes, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = allowMultiple
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentMediaPicker

        init(parent: DocumentMediaPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            var tempURLs: [URL] = []

            for url in urls {
                let shouldStop = url.startAccessingSecurityScopedResource()
                defer { if shouldStop { url.stopAccessingSecurityScopedResource() } }

                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(UUID().uuidString)_\(url.lastPathComponent)")

                try? FileManager.default.removeItem(at: tempURL)
                do {
                    try FileManager.default.copyItem(at: url, to: tempURL)
                    tempURLs.append(tempURL)
                } catch {
                    debugLog("Failed to copy file: \(error)")
                }
            }

            DispatchQueue.main.async {
                self.parent.selectedURLs = tempURLs
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}
