// ┌──────────────────────────────────────────────────────────────┐
// │  MODULE  : StorageKit                                         │
// │  FICHIER : Database/Engines/SQLiteEngine+Search.swift        │
// │  INTERNE — implémente SearchCapableEngine                    │
// │                                                              │
// │  Toutes les méthodes statiques sont synchrones               │
// │  (cohérent avec SQLiteEngine.swift).                         │
// └──────────────────────────────────────────────────────────────┘

import Foundation
import GRDB
import WaanguCoreKit

// ─────────────────────────────────────────────────────────────
// MARK: SearchCapableEngine — protocol INTERNE
// ─────────────────────────────────────────────────────────────

protocol SearchCapableEngine: DatabaseEngine {
    func engineSearch(
        keyword:   String,
        in types:  [any Storable.Type],
        namespace: String,
        limit:     Int
    ) async throws -> SearchResults

    func engineFetchJoined<Root, Related>(
        _ root:     Root.Type,
        joinedTo:   Related.Type,
        on keyPath: KeyPath<Root, Related.ID?>,
        rootQuery:  QuerySpec?,
        namespace:  String
    ) async throws -> [(root: Root, related: Related?)]
    where Root: Storable, Related: Storable

    func engineFetchWithChildren<Root, Child>(
        _ root:     Root.Type,
        children:   Child.Type,
        on keyPath: KeyPath<Child, Root.ID>,
        rootQuery:  QuerySpec?,
        namespace:  String
    ) async throws -> [(root: Root, children: [Child])]
    where Root: Storable, Child: Storable

    func engineFetchRaw<T: Storable>(
        _ type:     T.Type,
        rawQuery:   String,
        arguments:  [AnyStorableArgument],
        namespace:  String
    ) async throws -> [T]

    func engineFetchAggregate(
        rawQuery:   String,
        arguments:  [AnyStorableArgument],
        namespace:  String
    ) async throws -> [[String: Any]]
}

// ─────────────────────────────────────────────────────────────
// MARK: SQLiteEngine + SearchCapableEngine
// ─────────────────────────────────────────────────────────────

extension SQLiteEngine: SearchCapableEngine {

    // ─────────────────────────────────────────────────────────
    // MARK: Full-text search FTS5
    // ─────────────────────────────────────────────────────────

    func engineSearch(
        keyword:   String,
        in types:  [any Storable.Type],
        namespace: String,
        limit:     Int
    ) async throws -> SearchResults {
        let q     = try await gatedQueue(for: namespace)
        let start = ContinuousClock.now

        let groups = try SQLiteEngine.performSearch(
            q: q, keyword: keyword, types: types, limit: limit
        )

        let duration = ContinuousClock.now - start
        return SearchResults(
            groups: groups, keyword: keyword, durationMs: duration.milliseconds
        )
    }

    static func performSearch(
        q:       DatabaseQueue,
        keyword: String,
        types:   [any Storable.Type],
        limit:   Int
    ) throws -> [String: [SearchHit]] {
        try q.read { db in
            var groups: [String: [SearchHit]] = [:]
            for type in types {
                let typeName  = "\(type)"
                let ftsTable  = SQLiteSchemaBuilder.ftsTableName(for: type)
                let mainTable = SQLiteSchemaBuilder.tableName(for: type)

                let ftsExists = (try? Bool.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) > 0 FROM sqlite_master WHERE type='table' AND name=?",
                    arguments: [ftsTable]
                )) ?? false
                guard ftsExists else { continue }

                let rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT
                            m.id,
                            m.json_payload,
                            snippet(\(ftsTable), 0, '<b>', '</b>', '...', 20) AS snippet,
                            bm25(\(ftsTable)) AS rank
                        FROM \(ftsTable)
                        JOIN \(mainTable) m ON m.rowid = \(ftsTable).rowid
                        WHERE \(ftsTable) MATCH ?
                        ORDER BY rank
                        LIMIT ?
                        """,
                    arguments: [keyword, limit]
                )

                groups[typeName] = rows.map { row in
                    SearchHit(
                        id:         row["id"] ?? "",
                        entityType: typeName,
                        snippet:    row["snippet"] ?? "",
                        rank:       abs(row["rank"] ?? 0.0),
                        rawData:    row["json_payload"] ?? Data()
                    )
                }
            }
            return groups
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: fetchJoined — relation 1-1
    // ─────────────────────────────────────────────────────────

    func engineFetchJoined<Root, Related>(
        _ root:     Root.Type,
        joinedTo:   Related.Type,
        on keyPath: KeyPath<Root, Related.ID?>,
        rootQuery:  QuerySpec?,
        namespace:  String
    ) async throws -> [(root: Root, related: Related?)]
    where Root: Storable, Related: Storable {
        let q   = try await gatedQueue(for: namespace)
        let dec = decoder
        return try SQLiteEngine.performFetchJoined(
            q: q, root: root, joinedTo: Related.self,
            on: keyPath, rootQuery: rootQuery,
            namespace: namespace, decoder: dec
        )
    }

    static func performFetchJoined<Root, Related>(
        q:         DatabaseQueue,
        root:      Root.Type,
        joinedTo:  Related.Type,
        on keyPath: KeyPath<Root, Related.ID?>,
        rootQuery: QuerySpec?,
        namespace: String,
        decoder:   JSONDecoder
    ) throws -> [(root: Root, related: Related?)]
    where Root: Storable, Related: Storable {
        try q.read { db in
            let roots = try SQLiteEngine.fetchFromDedicatedTable(
                root, namespace: namespace, query: rootQuery, db: db, decoder: decoder
            )
            guard !roots.isEmpty else { return [] }

            let relatedIds = roots
                .compactMap { $0[keyPath: keyPath] }
                .map { "\($0)" }
            guard !relatedIds.isEmpty else {
                return roots.map { ($0, nil) }
            }

            let relatedTable = SQLiteSchemaBuilder.tableName(for: Related.self)
            let placeholders = relatedIds.map { _ in "?" }.joined(separator: ",")
            let relatedRows  = try Row.fetchAll(
                db,
                sql: "SELECT * FROM \(relatedTable) WHERE id IN (\(placeholders))",
                arguments: StatementArguments(relatedIds)
            )

            let relatedObjects = relatedRows.compactMap { row -> Related? in
                guard let data = row["json_payload"] as? Data else { return nil }
                return try? decoder.decode(Related.self, from: data)
            }

            let relatedMap = Dictionary(
                uniqueKeysWithValues: relatedObjects.map { ($0.id, $0) }
            )
            return roots.map { r in
                (r, r[keyPath: keyPath].flatMap { relatedMap[$0] })
            }
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: fetchWithChildren — relation 1-N
    // ─────────────────────────────────────────────────────────

    func engineFetchWithChildren<Root, Child>(
        _ root:     Root.Type,
        children:   Child.Type,
        on keyPath: KeyPath<Child, Root.ID>,
        rootQuery:  QuerySpec?,
        namespace:  String
    ) async throws -> [(root: Root, children: [Child])]
    where Root: Storable, Child: Storable {
        let q   = try await gatedQueue(for: namespace)
        let dec = decoder
        return try SQLiteEngine.performFetchWithChildren(
            q: q, root: root, children: Child.self,
            on: keyPath, rootQuery: rootQuery,
            namespace: namespace, decoder: dec
        )
    }

    static func performFetchWithChildren<Root, Child>(
        q:         DatabaseQueue,
        root:      Root.Type,
        children:  Child.Type,
        on keyPath: KeyPath<Child, Root.ID>,
        rootQuery: QuerySpec?,
        namespace: String,
        decoder:   JSONDecoder
    ) throws -> [(root: Root, children: [Child])]
    where Root: Storable, Child: Storable {
        try q.read { db in
            let roots = try SQLiteEngine.fetchFromDedicatedTable(
                root, namespace: namespace, query: rootQuery, db: db, decoder: decoder
            )
            guard !roots.isEmpty else { return [] }

            let parentIds    = roots.map { "\($0.id)" }
            let placeholders = parentIds.map { _ in "?" }.joined(separator: ",")
            let childTable   = SQLiteSchemaBuilder.tableName(for: Child.self)
            let fkColumn     = SQLiteEngine.columnName(for: keyPath, on: Child.self)

            let childRows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM \(childTable) WHERE \(fkColumn) IN (\(placeholders))",
                arguments: StatementArguments(parentIds)
            )

            let allChildren = childRows.compactMap { row -> Child? in
                guard let data = row["json_payload"] as? Data else { return nil }
                return try? decoder.decode(Child.self, from: data)
            }

            let childrenByParent = Dictionary(grouping: allChildren) { child in
                "\(child[keyPath: keyPath])"
            }
            return roots.map { r in (r, childrenByParent["\(r.id)"] ?? []) }
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: fetchRaw — requête custom avec décodage JSON
    // ─────────────────────────────────────────────────────────

    func engineFetchRaw<T: Storable>(
        _ type:     T.Type,
        rawQuery:   String,
        arguments:  [AnyStorableArgument],
        namespace:  String
    ) async throws -> [T] {
        let q    = try await gatedQueue(for: namespace)
        let dec  = decoder
        let args = arguments.compactMap { $0.asDatabaseValue }
        return try SQLiteEngine.performRawFetch(
            type, rawQuery: rawQuery, args: args, q: q, decoder: dec
        )
    }

    static func performRawFetch<T: Storable>(
        _ type:   T.Type,
        rawQuery: String,
        args:     [DatabaseValueConvertible],
        q:        DatabaseQueue,
        decoder:  JSONDecoder
    ) throws -> [T] {
        try q.read { db in
            try Row.fetchAll(
                db, sql: rawQuery, arguments: StatementArguments(args)
            ).compactMap { row in
                guard let data = row["json_payload"] as? Data else { return nil }
                return try? decoder.decode(type, from: data)
            }
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: fetchAggregate — requête d'agrégation brute
    // ─────────────────────────────────────────────────────────

    func engineFetchAggregate(
        rawQuery:   String,
        arguments:  [AnyStorableArgument],
        namespace:  String
    ) async throws -> [[String: Any]] {
        let q    = try await gatedQueue(for: namespace)
        let args = arguments.compactMap { $0.asDatabaseValue }
        return try SQLiteEngine.performRawAggregate(
            rawQuery: rawQuery, args: args, q: q
        )
    }

    static func performRawAggregate(
        rawQuery: String,
        args:     [DatabaseValueConvertible],
        q:        DatabaseQueue
    ) throws -> [[String: Any]] {
        try q.read { db in
            try Row.fetchAll(
                db, sql: rawQuery, arguments: StatementArguments(args)
            ).map { row in
                Dictionary(uniqueKeysWithValues: row.columnNames.map { col in
                    (col, row[col] as Any)
                })
            }
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Helpers
    // ─────────────────────────────────────────────────────────

    static func columnName<T, V>(
        for keyPath: KeyPath<T, V>,
        on type: T.Type
    ) -> String {
        let name = String(describing: keyPath)
            .components(separatedBy: ".")
            .last ?? "id"
        return camelToSnake(name)
    }

    private static func camelToSnake(_ input: String) -> String {
        var result = ""
        for char in input {
            if char.isUppercase {
                if !result.isEmpty { result += "_" }
                result += char.lowercased()
            } else {
                result += String(char)
            }
        }
        return result
    }
}
