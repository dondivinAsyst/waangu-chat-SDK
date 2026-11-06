//
//  DatabaseTransactionTests.swift
//  StorageKitTests
//
//  B51 — `withTransaction` sur le moteur SQLite réel.
//
//  Avant (B49), le moteur ouvrait et relâchait un SAVEPOINT dans deux écritures
//  GRDB distinctes : le commit échouait toujours, même pour un bloc vide, et le
//  rollback ne défaisait rien (reproduit le 2026-10-09, build/b49-repro.xcresult).
//  Désormais une vraie transaction : le bloc commit ou s'annule en entier, et
//  une écriture d'une autre tâche attend la fin de la transaction.
//

import XCTest
@testable import WaanguStorageKit
import WaanguCoreKit

final class DatabaseTransactionTests: XCTestCase {

    private struct Note: Storable {
        static let namespace = "txtest"
        var id: String
        var text: String
    }

    private struct Boom: Error {}

    private actor Flag {
        private(set) var raised = false
        func raise() { raised = true }
    }

    /// Base fraîche, namespace déjà prêt : la transaction couvre les namespaces initialisés.
    private func makeStore() async throws -> any SearchableDatabaseProtocol {
        let store = DatabaseAssembly.makeSearchable()
        try await store.save(Note(id: "seed-\(UUID().uuidString)", text: "seed"))
        return store
    }

    private func note(_ text: String) -> Note { Note(id: "\(text)-\(UUID().uuidString)", text: text) }

    func test_emptyTransaction_commits() async throws {
        let store = try await makeStore()

        try await store.withTransaction { }
    }

    func test_writesInsideATransaction_commitTogether() async throws {
        let store = try await makeStore()
        let first = note("un")
        let second = note("deux")

        try await store.withTransaction {
            try await store.save(first)
            try await store.save(second)
        }

        let storedFirst = try await store.fetchOne(Note.self, id: first.id)
        let storedSecond = try await store.fetchOne(Note.self, id: second.id)
        XCTAssertEqual(storedFirst?.text, "un")
        XCTAssertEqual(storedSecond?.text, "deux")
    }

    /// Le bloc lève après deux écritures : aucune ne reste.
    func test_throwingBlock_rollsBackEveryWrite() async throws {
        let store = try await makeStore()
        let first = note("annulé-1")
        let second = note("annulé-2")

        do {
            try await store.withTransaction {
                try await store.save(first)
                try await store.save(second)
                throw Boom()
            }
            XCTFail("the transaction should have thrown")
        } catch DatabaseError.transactionFailed {}

        let storedFirst = try await store.fetchOne(Note.self, id: first.id)
        let storedSecond = try await store.fetchOne(Note.self, id: second.id)
        XCTAssertNil(storedFirst)
        XCTAssertNil(storedSecond)
    }

    /// Le bloc lit ce qu'il vient d'écrire, avant le commit.
    func test_blockReadsItsOwnUncommittedWrites() async throws {
        let store = try await makeStore()
        let written = note("lu")

        let seen = try await store.withTransaction { () -> String? in
            try await store.save(written)
            return try await store.fetchOne(Note.self, id: written.id)?.text
        }

        XCTAssertEqual(seen, "lu")
    }

    /// Une écriture d'une autre tâche attend la fin de la transaction : elle
    /// n'y entre pas, et n'est donc pas annulée avec elle.
    func test_writeFromAnotherTask_waitsForTheTransaction_andSurvivesItsRollback() async throws {
        let store = try await makeStore()
        let outsider = note("dehors")
        let inside = note("dedans")
        let outsiderDone = Flag()
        var outsiderTask: Task<Void, Error>?

        do {
            try await store.withTransaction {
                try await store.save(inside)
                // Détachée : n'hérite pas du jeton de la transaction.
                outsiderTask = Task.detached {
                    try await store.save(outsider)
                    await outsiderDone.raise()
                }
                try await Task.sleep(nanoseconds: 300_000_000)
                let doneDuringTransaction = await outsiderDone.raised
                XCTAssertFalse(doneDuringTransaction, "the outside write must wait for the transaction")
                throw Boom()
            }
        } catch DatabaseError.transactionFailed {}

        try await outsiderTask?.value
        let storedInside = try await store.fetchOne(Note.self, id: inside.id)
        let storedOutsider = try await store.fetchOne(Note.self, id: outsider.id)
        XCTAssertNil(storedInside, "rolled back")
        XCTAssertEqual(storedOutsider?.text, "dehors", "the outside write ran after the rollback")
    }

    /// Le namespace s'ouvre pour la première fois dans le bloc (première
    /// synchronisation après installation) : il rejoint la transaction.
    func test_namespaceOpenedInsideTheBlock_joinsTheTransaction() async throws {
        let store = DatabaseAssembly.makeSearchable()
        let written = note("tardif")

        do {
            try await store.withTransaction {
                try await store.save(written)
                throw Boom()
            }
            XCTFail("the transaction should have thrown")
        } catch DatabaseError.transactionFailed {}

        let stored = try await store.fetchOne(Note.self, id: written.id)
        XCTAssertNil(stored, "rolled back with the transaction")
    }

    /// Deux transactions démarrées au même instant par des tâches différentes
    /// passent l'une après l'autre. Avant, le moteur ne se déclarait propriétaire
    /// qu'*après* l'`await` du `BEGIN` : une seconde tâche franchissait la porte
    /// dans l'intervalle et SQLite refusait « cannot start a transaction within
    /// a transaction » (vu en direct le 2026-10-14, deux synchronisations qui se
    /// chevauchaient au lancement).
    func test_transactionsStartedAtTheSameTime_runOneAfterTheOther() async throws {
        let store = try await makeStore()

        // A race: one round proves little, so the same situation is repeated.
        for round in 0..<15 {
            let notes = (0..<8).map { note("simultanee-\(round)-\($0)") }

            try await withThrowingTaskGroup(of: Void.self) { group in
                for item in notes {
                    group.addTask {
                        try await store.withTransaction {
                            try await store.save(item)
                        }
                    }
                }
                try await group.waitForAll()
            }

            for item in notes {
                let stored = try await store.fetchOne(Note.self, id: item.id)
                XCTAssertEqual(stored?.text, item.text, "round \(round): every transaction must commit")
            }
        }
    }

    func test_nestedTransaction_isRefused() async throws {
        let store = try await makeStore()

        do {
            try await store.withTransaction {
                try await store.withTransaction { }
            }
            XCTFail("a nested transaction must be refused")
        } catch DatabaseError.transactionFailed(let underlying) {
            guard case DatabaseError.transactionFailed(let inner) = underlying,
                  case DatabaseError.transactionAlreadyActive = inner else {
                return XCTFail("unexpected error: \(underlying)")
            }
        }
    }
}
