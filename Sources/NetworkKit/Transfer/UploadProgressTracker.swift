// MARK: - NetworkKit/Transfer/UploadProgressTracker.swift

import Foundation
import Combine

@MainActor
public class UploadProgressTracker: ObservableObject {

    @Published public var progress: Double = 0.0
    @Published public var isUploading: Bool = false
    @Published public var uploadedBytes: Int64 = 0
    @Published public var totalBytes: Int64 = 0

    public init() {}

    public func startUpload(totalBytes: Int64) {
        self.totalBytes = totalBytes
        self.uploadedBytes = 0
        self.progress = 0.0
        self.isUploading = true
    }

    public func updateProgress(uploadedBytes: Int64) {
        self.uploadedBytes = uploadedBytes
        if totalBytes > 0 {
            self.progress = Double(uploadedBytes) / Double(totalBytes)
        }
    }

    public func finishUpload() {
        self.isUploading = false
        self.progress = 1.0
    }

    public func cancelUpload() {
        self.isUploading = false
        self.progress = 0.0
    }
}
