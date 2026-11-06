//
//  TemporaryFileStoreProtocol.swift
//  AppModules
//
//  Created by Asyst on 3/30/26.
//

import Foundation

public protocol TemporaryFileStoreProtocol: Sendable {
    func write(data: Data, fileName: String) async throws -> URL
    func read(fileName: String) async throws -> Data
    func delete(fileName: String) async throws
    func exists(fileName: String) async -> Bool
    func url(for fileName: String) async -> URL
    func clearAll() async throws
    func listFiles() async throws -> [String]
    func uniqueFileName(extension ext: String) async -> String
}
