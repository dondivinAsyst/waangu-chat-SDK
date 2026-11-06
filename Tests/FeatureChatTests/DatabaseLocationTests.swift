//
//  DatabaseLocationTests.swift
//  FeatureChatTests
//
//  Plan SDK, direction A — le renommage des modules (CoreKit -> WaanguCoreKit, ...) ne doit pas
//  déplacer la base locale. Le dossier est écrit en dur (« StorageKit/Database ») : si un
//  remplacement de texte le changeait, chaque utilisateur perdrait ses conversations locales à la
//  mise à jour, sans erreur.
//
//  Ce test enregistre une ligne de chat puis vérifie que le fichier SQLite existe exactement là
//  où les versions précédentes l'écrivaient.
//

import XCTest
import WaanguCoreKit
import WaanguStorageKit
@testable import WaanguFeatureChat

final class DatabaseLocationTests: XCTestCase {

    func test_theChatDatabase_staysWhereEarlierVersionsWroteIt() async throws {
        // The simulator keeps the database between runs, so the file existing is not proof: this
        // run must be the one that wrote it.
        let started = Date().addingTimeInterval(-1)
        let store = DatabaseAssembly.makeSearchable(
            config: .init(engine: .sqlite, migrationSteps: ChatDatabaseRegistration.migrationSteps))
        await DatabaseAssembly.register(ChatDatabaseRegistration.self, in: store)
        let conversation = ConversationModel(id: "location-\(UUID().uuidString)", type: .direct)
        try await store.save(conversation)
        addTeardownBlock { try? await store.delete(ConversationModel.self, id: conversation.id) }

        let expected = URL.documentsDirectory
            .appending(path: "StorageKit/Database", directoryHint: .isDirectory)
            .appending(path: "\(ConversationModel.namespace).sqlite")

        XCTAssertTrue(FileManager.default.fileExists(atPath: expected.path),
                      "the chat database is not at \(expected.path): a rename moved it")
        // SQLite may write to the side file (-wal) instead of the main file.
        let written = ["", "-wal", "-shm"].compactMap { suffix -> Date? in
            let attributes = try? FileManager.default.attributesOfItem(atPath: expected.path + suffix)
            return attributes?[.modificationDate] as? Date
        }.max()
        XCTAssertNotNil(written)
        XCTAssertGreaterThanOrEqual(written ?? .distantPast, started,
                                    "the file at \(expected.path) was not written by this run")
    }

    /// Les noms de dossiers qui portent des données ne suivent pas les noms de modules.
    func test_theFolderNameIsNotAModuleName() {
        let folder = URL.documentsDirectory.appending(path: "StorageKit/Database", directoryHint: .isDirectory)

        XCTAssertTrue(folder.path.hasSuffix("/StorageKit/Database"))
        XCTAssertFalse(folder.path.contains("WaanguStorageKit"))
    }
}
