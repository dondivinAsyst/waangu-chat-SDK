//
//  BackgroundUploadManager.swift
//  AppModules
//
//  Created by Don divin on 5/6/26.
//



import SwiftUI
import Combine
import WaanguCoreKit

final class BackgroundUploadManager: NSObject, URLSessionDelegate, URLSessionTaskDelegate {

    static let shared = BackgroundUploadManager()

    lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.yourapp.uploads")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    // Store completion handlers for each upload task
    private var completionHandlers: [Int: (Result<String, AppError>) -> Void] = [:]

    func setCompletion(for task: URLSessionTask, handler: @escaping (Result<String, AppError>) -> Void) {
        completionHandlers[task.taskIdentifier] = handler
    }

    // Called when a task completes
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard
            let handler = completionHandlers[task.taskIdentifier]
        else { return }

        defer { completionHandlers.removeValue(forKey: task.taskIdentifier) }

        if let error = error {
            handler(.failure(.unknown(error.localizedDescription)))
            return
        }

        guard let response = task.response as? HTTPURLResponse else {
            handler(.failure(.unknown("No response")))
            return
        }

        guard response.statusCode == 200 else {
            handler(.failure(.unknown("Upload failed (\(response.statusCode))")))
            return
        }

        // Extract ETag
        let eTag = response.value(forHTTPHeaderField: "ETag") ?? ""
        if eTag.isEmpty {
            handler(.failure(.unknown(ChatErrorStrings.uploadIncomplete)))
        } else {
            handler(.success(eTag))
        }
    }
}
