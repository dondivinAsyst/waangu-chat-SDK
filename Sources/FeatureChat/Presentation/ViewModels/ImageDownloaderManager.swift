//import SwiftUI
//import Combine
//
//class ImageDownloader: ObservableObject {
//    @Published var image: UIImage? = nil
//    @Published var isLoading = false
//    @Published var hasError = false
//
//    private var cancellable: AnyCancellable?
//
//    func downloadImage(from urlString: String) {
//      
//        guard let url = URL(string: urlString) else { return }
//
//        isLoading = true
//        hasError = false
//        image = nil
//
//        cancellable = URLSession.shared.dataTaskPublisher(for: url)
//            .map { UIImage(data: $0.data) }
//            .receive(on: DispatchQueue.main)
//            .sink(receiveCompletion: { completion in
//                self.isLoading = false
//                if case .failure(_) = completion {
//                    self.hasError = true
//                    print("this was called change 11",self.hasError)
//                }
//            }, receiveValue: { img in
//                self.image = img
//            })
//    }
//
//    func retry(_ url: String) {
//        downloadImage(from: url)
//    }
//}

import SwiftUI
import WaanguSharedUI
import Combine

class ImageDownloader: ObservableObject {
    @Published var image: UIImage?
    @Published var progress: Double = 0
    @Published var isLoading = false
    @Published var hasError = false

    var downloadTask: Task<Void, Never>?
    /// Fired on the main actor after a successful download is written to `.STATUS` disk cache.
    var onDiskCached: ((String) -> Void)?

    func downloadImage(from urlString: String, codeStatus: String = "") {
        // Prefer on-disk cache (saved after first successful download).
        if !codeStatus.isEmpty,
           let cached = DiskMediaManager.shared.loadImageFromDisk(fileName: codeStatus, pathName: .STATUS) {
            image = cached
            progress = 1
            hasError = false
            isLoading = false
            return
        }

        guard let url = URL(string: urlString), !urlString.isEmpty else {
            hasError = true
            isLoading = false
            return
        }

        image = nil
        progress = 0
        hasError = false
        isLoading = true

        downloadTask?.cancel()

        downloadTask = Task {
            do {
                let (stream, response) = try await URLSession.shared.bytes(from: url)

                let expectedSize = response.expectedContentLength
                var received: Int64 = 0
                var buffer = Data(capacity: expectedSize > 0 ? Int(expectedSize) : 1_000_000)

                for try await chunk in stream.chunked(by: 32 * 1024) {
                    buffer.append(contentsOf: chunk)
                    received += Int64(chunk.count)

                    if expectedSize > 0 {
                        await MainActor.run {
                            self.progress = Double(received) / Double(expectedSize)
                        }
                    }
                }

                let downloaded = UIImage(data: buffer)
                // Persist before publishing image so strip refresh can read from disk.
                if let downloaded, !codeStatus.isEmpty {
                    DiskMediaManager.shared.saveImageToDisk(
                        downloaded,
                        fileName: codeStatus,
                        pathName: .STATUS
                    )
                }
                await MainActor.run {
                    self.image = downloaded
                    self.isLoading = false
                    if downloaded != nil, !codeStatus.isEmpty {
                        self.onDiskCached?(codeStatus)
                    }
                }
            } catch is CancellationError {
                // Ignore
            } catch {
                await MainActor.run {
                    self.hasError = true
                    self.isLoading = false
                }
            }
        }
    }

    func reset() {
        image = nil
        progress = 0
        isLoading = false
        hasError = false
    }

    func retry(_ url: String, codeStatus: String = "") {
        downloadImage(from: url, codeStatus: codeStatus)
    }
}
