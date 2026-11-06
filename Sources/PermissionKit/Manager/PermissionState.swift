//
//  PermissionState.swift
//  AppModules
//
//  Created by Asyst on 3/24/26.
//

import Foundation
import WaanguCoreKit

/// État interne du PermissionCenter, isolé dans un actor.
///
/// Gère les continuations de streams par type de permission
/// et le cache du dernier statut connu (pour éviter les yields redondants).
actor PermissionState {

    private struct StreamEntry {
        let id: UUID
        let continuation: AsyncStream<PermissionStatus>.Continuation
    }

    private var streams: [PermissionType: [StreamEntry]] = [:]
    private var lastKnownStatus: [PermissionType: PermissionStatus] = [:]

    // MARK: - Stream Management

    func addContinuation(
        _ continuation: AsyncStream<PermissionStatus>.Continuation,
        for type: PermissionType
    ) -> UUID {
        let id = UUID()
        streams[type, default: []].append(StreamEntry(id: id, continuation: continuation))
        return id
    }

    func removeContinuation(_ id: UUID, for type: PermissionType) {
        streams[type]?.removeAll { $0.id == id }
        if streams[type]?.isEmpty == true {
            streams.removeValue(forKey: type)
        }
    }

    // MARK: - Publishing

    /// Publie un nouveau statut uniquement s'il a changé depuis la dernière émission.
    func publish(status: PermissionStatus, for type: PermissionType) {
        guard lastKnownStatus[type] != status else { return }
        lastKnownStatus[type] = status

        guard let entries = streams[type] else { return }
        for entry in entries {
            entry.continuation.yield(status)
        }
    }

    /// Force la publication (utilisé pour l'état initial, sans check de déduplication).
    func forcePublish(status: PermissionStatus, for type: PermissionType) {
        lastKnownStatus[type] = status
        guard let entries = streams[type] else { return }
        for entry in entries {
            entry.continuation.yield(status)
        }
    }

    func getLastKnownStatus(for type: PermissionType) -> PermissionStatus? {
        lastKnownStatus[type]
    }
}
