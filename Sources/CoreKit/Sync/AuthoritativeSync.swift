import Foundation

public actor AuthoritativeSync {
    
    public static let shared = AuthoritativeSync()
    
    private var deviceStates: [String: DeviceSyncState] = [:]
    private var vectorClocks: [String: VectorClock] = [:]
    private let currentDeviceId: String
    
    private init() {
        self.currentDeviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    }
    
    public func syncData<T: Syncable>(
        _ data: T,
        fromDevice deviceId: String
    ) async throws -> SyncDecision<T> {
        
        let entityId = data.syncId
        var clock = vectorClocks[entityId] ?? VectorClock()
        
        let localVersion = clock.version(for: currentDeviceId)
        let remoteVersion = data.vectorClock.version(for: deviceId)
        
        if remoteVersion <= localVersion {
            return .reject(reason: "Stale data from device \(deviceId)")
        }
        
        if let existing = try? await loadLocal(entityId: entityId, as: T.self) {
            let decision = resolveConflict(local: existing, remote: data)
            
            switch decision {
            case .useLocal:
                return .reject(reason: "Local data has higher priority")
            case .useRemote:
                clock.increment(for: deviceId)
                vectorClocks[entityId] = clock
                return .accept(data: data, merged: false)
            case .merge(let merged):
                clock.increment(for: currentDeviceId)
                vectorClocks[entityId] = clock
                return .accept(data: merged, merged: true)
            }
        }
        
        clock.increment(for: deviceId)
        vectorClocks[entityId] = clock
        return .accept(data: data, merged: false)
    }
    
    public func prepareForSync<T: Syncable>(_ data: T) async -> T {
        var mutableData = data
        var clock = vectorClocks[data.syncId] ?? VectorClock()
        clock.increment(for: currentDeviceId)
        vectorClocks[data.syncId] = clock
        mutableData.vectorClock = clock
        mutableData.lastModifiedDevice = currentDeviceId
        return mutableData
    }
    
    public func getDeviceState(_ deviceId: String) -> DeviceSyncState? {
        deviceStates[deviceId]
    }
    
    public func updateDeviceState(_ deviceId: String, lastSeen: Date, syncVersion: Int64) {
        deviceStates[deviceId] = DeviceSyncState(
            deviceId: deviceId,
            lastSeen: lastSeen,
            syncVersion: syncVersion
        )
    }
    
    private func resolveConflict<T: Syncable>(local: T, remote: T) -> ConflictResolution<T> {
        if local.truthSource.priority > remote.truthSource.priority {
            return .useLocal
        }
        
        if remote.truthSource.priority > local.truthSource.priority {
            return .useRemote
        }
        
        if remote.lastModifiedAt > local.lastModifiedAt {
            return .useRemote
        }
        
        if local.lastModifiedAt > remote.lastModifiedAt {
            return .useLocal
        }
        
        // Bloc 8, §17 — le merge local est **interdit** pour tout objet dont la
        // vérité est au serveur : montant, devise, settlement, statut de
        // transaction, décision Compliance, permis d'exécution.
        //
        // La porte est ici plutôt que dans le type parce que `merge` est déclaré
        // sur `Syncable` sans contrainte : n'importe quel objet financier
        // pouvait emprunter ce chemin. Refuser à la résolution ferme le chemin
        // pour tous, y compris les conformances écrites plus tard.
        guard local.allowsLocalMerge else { return .useRemote }

        if let merged = local.merge(with: remote) {
            return .merge(merged)
        }
        
        return .useRemote
    }
    
    private func loadLocal<T: Syncable>(entityId: String, as type: T.Type) async throws -> T? {
        return nil
    }
}

public protocol Syncable: Codable, Sendable {
    var syncId: String { get }
    var vectorClock: VectorClock { get set }
    var lastModifiedAt: Date { get }
    var lastModifiedDevice: String { get set }
    var truthSource: TruthSource { get }
    
    func merge(with other: Self) -> Self?

    /// `false` interdit toute fusion locale de cet objet.
    ///
    /// Bloc 8, §17. La valeur par défaut lie l'autorisation à ``truthSource`` :
    /// un objet dont la vérité est au backend ne se fusionne pas ici, jamais.
    /// Un type qui veut fusionner doit le déclarer explicitement — l'oubli
    /// ferme, il n'ouvre pas.
    var allowsLocalMerge: Bool { get }
}

public extension Syncable {

    var allowsLocalMerge: Bool { truthSource != .backend }
}

public struct VectorClock: Codable, Sendable {
    private var versions: [String: Int64] = [:]
    
    public init() {}
    
    public mutating func increment(for deviceId: String) {
        versions[deviceId, default: 0] += 1
    }
    
    public func version(for deviceId: String) -> Int64 {
        versions[deviceId] ?? 0
    }
    
    public func happenedBefore(_ other: VectorClock) -> Bool {
        var strictlyLess = false
        for (device, version) in versions {
            let otherVersion = other.version(for: device)
            if version > otherVersion {
                return false
            }
            if version < otherVersion {
                strictlyLess = true
            }
        }
        return strictlyLess
    }
    
    public func concurrent(with other: VectorClock) -> Bool {
        !happenedBefore(other) && !other.happenedBefore(self)
    }
}

public struct DeviceSyncState: Sendable {
    public let deviceId: String
    public let lastSeen: Date
    public let syncVersion: Int64
}

public enum SyncDecision<T: Syncable>: Sendable {
    case accept(data: T, merged: Bool)
    case reject(reason: String)
}

private enum ConflictResolution<T: Syncable> {
    case useLocal
    case useRemote
    case merge(T)
}

#if canImport(UIKit)
import UIKit
#endif
