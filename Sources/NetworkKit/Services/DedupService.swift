// MARK: - NetworkKit/Services/DedupService.swift

import Foundation

// MARK: - Protocol

public protocol DedupService: Sendable {
    func execute<T>(
        endpointKey: String,
        task: @escaping () async throws -> T
    ) async throws -> T
}

// MARK: - Implementation

public actor DedupServiceImpl: DedupService {

    /// Wrapper type-erasé pour stocker des `Task<T, Error>` hétérogènes.
    /// Cast isolé ici — protégé par vérification de type explicite.
    private struct AnyTask {
        private let _value: () async throws -> Any
        let cancel: () -> Void

        init<T>(_ task: Task<T, Error>) {
            _value = { try await task.value }
            cancel = { task.cancel() }
        }

        func value<T>(as type: T.Type) async throws -> T {
            let result = try await _value()
            guard let typed = result as? T else {
                throw DedupError.typeMismatch(
                    expected: "\(T.self)",
                    got: "\(Swift.type(of: result))"
                )
            }
            return typed
        }
    }

    public enum DedupError: Error {
        case typeMismatch(expected: String, got: String)
    }

    private var inFlightTasks: [String: AnyTask] = [:]

    public init() {}

    /// Exécute `task` ou joint une task identique déjà en vol.
    /// Les appelants concurrents avec la même `endpointKey` partagent le même résultat.
    public func execute<T>(
        endpointKey: String,
        task: @escaping () async throws -> T
    ) async throws -> T {
        if let existing = inFlightTasks[endpointKey] {
            return try await existing.value(as: T.self)
        }

        let newTask = Task<T, Error> { try await task() }
        inFlightTasks[endpointKey] = AnyTask(newTask)
        defer { inFlightTasks[endpointKey] = nil }

        return try await newTask.value
    }
}
