//
//  ShareContentView.swift
//  FeatureChat
//
//  Created by Kiro AI

import SwiftUI
import WaanguCoreKit

/// View that processes shared content from Share Extension
struct ShareContentView: View {
    private let shareProcessor: ShareContentProcessorProtocol
    private let url: URL
    private let translationService: (any TranslationServiceProtocol)?
    
    @State private var isProcessing = false
    @State private var processingError: String?
    
    init(
        url: URL,
        shareProcessor: ShareContentProcessorProtocol,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        self.url = url
        self.shareProcessor = shareProcessor
        self.translationService = translationService
    }
    
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            
            VStack(spacing: 20) {
                if isProcessing {
                    ProgressView(t(ChatTranslationKeys.SHARE_PROCESSING))
                        .progressViewStyle(CircularProgressViewStyle())
                } else if let error = processingError {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        
                        Text(t(ChatTranslationKeys.SHARE_FAILED_TITLE))
                            .font(.headline)
                        
                        Text(error)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button(t(ChatTranslationKeys.SHARE_TRY_AGAIN)) {
                            processSharedContent()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.green)
                        
                        Text(t(ChatTranslationKeys.SHARE_SUCCESS_TITLE))
                            .font(.headline)
                        
                        Text(t(ChatTranslationKeys.SHARE_SUCCESS_MESSAGE))
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding()
        }
        .onAppear {
            processSharedContent()
        }
    }
    
    private func processSharedContent() {
        Task {
            await processContentAsync()
        }
    }
    
    @MainActor
    private func processContentAsync() async {
        isProcessing = true
        processingError = nil
        
        do {
            try await shareProcessor.processSharedContent(from: url)
            // Content processed successfully
            isProcessing = false
            
            // Optionally dismiss after a delay or navigate to chat list
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                // TODO: Navigate to chat list or dismiss modal
            }
            
        } catch {
            isProcessing = false
            processingError = error.localizedDescription
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

#Preview {
    ShareContentView(
        url: URL(string: "chat://share?type=text&text=Hello+World&destination=contacts&contactIds=user1,user2")!,
        shareProcessor: MockShareProcessor()
    )
}

// MARK: - Mock for Preview

class MockShareProcessor: ShareContentProcessorProtocol {
    func processSharedContent(from url: URL) async throws {
        // Simulate processing delay
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
    }
}