//
//  FileStoreError.swift
//  AppModules
//
//  Created by Asyst on 3/24/26.
//

import Foundation

public enum FileStoreError: Error, LocalizedError, Sendable {

    case writeFailed(fileName: String, underlying: String)
    case readFailed(fileName: String, underlying: String)
    case deleteFailed(fileName: String, underlying: String)
    case fileNotFound(fileName: String)
    case directoryCleanupFailed(underlying: String)

    public var errorDescription: String? {
        switch self {
        case .writeFailed(let name, let msg):
            return "Failed to write '\(name)': \(msg)"
        case .readFailed(let name, let msg):
            return "Failed to read '\(name)': \(msg)"
        case .deleteFailed(let name, let msg):
            return "Failed to delete '\(name)': \(msg)"
        case .fileNotFound(let name):
            return "File not found: '\(name)'"
        case .directoryCleanupFailed(let msg):
            return "Directory cleanup failed: \(msg)"
        }
    }
}
