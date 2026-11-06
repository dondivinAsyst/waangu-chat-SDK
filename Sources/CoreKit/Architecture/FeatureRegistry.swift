//
//  FeatureRegistry.swift
//  AppModules
//
//  Created by Asyst on 3/23/26.
//
import Foundation


// MARK: - FeatureRegistryError

public enum FeatureRegistryError: Error, LocalizedError {
    case dependenciesProviderNotSet
    case dependenciesTypeMismatch(featureName: String)
    case featureLoadCancelled(String)

    public var errorDescription: String? {
        switch self {
        case .dependenciesProviderNotSet:
            return "FeatureRegistry.registerDependencies() must be called before feature(_:)."
        case .dependenciesTypeMismatch(let name):
            return "Dependency provider for '\(name)' returned the wrong type."
        case .featureLoadCancelled(let name):
            return "Loading '\(name)' was cancelled."
        }
    }
}

// MARK: - FeatureRegistry Actor

public actor FeatureRegistry {
    
    // MARK: - Singleton
    
    public static let shared = FeatureRegistry()
    private init() {}
    
    // MARK: - Private Properties
    
    private var loadedFeatures: [ObjectIdentifier: any Sendable] = [:]
    private var pendingTasks: [ObjectIdentifier: Task<any Sendable, Error>] = [:]
    private var dependencyProviders: [ObjectIdentifier: @Sendable () async throws -> any Sendable] = [:]
    private var priorities: [ObjectIdentifier: FeatureLoadPriority] = [:]
    
    // ✅ (2) Simplifié : plus de [weak self] inutile
    private var preloaders: [ObjectIdentifier: @Sendable () async -> Void] = [:]
    
    // ✅ (3) Tracking des tâches de preload pour contrôle du lifecycle
    private var activePreloadTask: Task<Void, Never>?
    
    // MARK: - Feature Access
    
    public func feature<F: FeatureLoadable>(_ type: F.Type) async throws -> F {
        let key = ObjectIdentifier(type)
        let name = String(describing: type)
        
        if let cached = loadedFeatures[key] as? F {
            return cached
        }
        
        // ✅ (1) Downcast runtime - acceptable dans ce design générique
        if let pendingTask = pendingTasks[key] {
            do {
                let result = try await pendingTask.value
                if let typedResult = result as? F {
                    return typedResult
                }
                // Type mismatch - on log et on continue
                debugLog("⚠️ FeatureRegistry: Type mismatch in pending task for \(name)")
                pendingTasks[key] = nil
            } catch {
                pendingTasks[key] = nil
            }
        }
        
        guard let provider = dependencyProviders[key] else {
            throw FeatureRegistryError.dependenciesProviderNotSet
        }
        
        let task = Task<any Sendable, Error> {
            let deps = try await provider()
            guard let typedDeps = deps as? F.Dependencies else {
                throw FeatureRegistryError.dependenciesTypeMismatch(featureName: name)
            }
            return try await F.load(dependencies: typedDeps)
        }
        
        pendingTasks[key] = task
        
        do {
            let loaded = try await task.value
            guard let typedLoaded = loaded as? F else {
                throw FeatureRegistryError.dependenciesTypeMismatch(featureName: name)
            }
            loadedFeatures[key] = typedLoaded
            pendingTasks[key] = nil
            return typedLoaded
        } catch is CancellationError {
            pendingTasks[key] = nil
            throw FeatureRegistryError.featureLoadCancelled(name)
        } catch {
            pendingTasks[key] = nil
            throw error
        }
    }
    
    // MARK: - Sync access
    
    public func featureIfLoaded<F: FeatureLoadable>(_ type: F.Type) -> F? {
        loadedFeatures[ObjectIdentifier(type)] as? F
    }
    
    // MARK: - Registration
    
    public func registerDependencies<F: FeatureLoadable>(
        for type: F.Type,
        priority: FeatureLoadPriority = .onDemand,
        provider: @escaping @Sendable () async throws -> F.Dependencies
    ) {
        let key = ObjectIdentifier(type)
        dependencyProviders[key] = provider
        priorities[key] = priority
        
        // ✅ (2) Pas besoin de [weak self] dans un actor
        preloaders[key] = {
            _ = try? await self.feature(F.self)
        }
    }
    
    // MARK: - Parallel preload by priority tier
    
    public func preloadFeatures(priority: FeatureLoadPriority) async {
        let keysToLoad = dependencyProviders.keys.filter { key in
            priorities[key] == priority
            && loadedFeatures[key] == nil
            && pendingTasks[key] == nil
        }
        
        let snapshot = keysToLoad.compactMap { preloaders[$0] }
        
        await withTaskGroup(of: Void.self) { group in
            for preloader in snapshot {
                group.addTask {
                    await preloader()
                }
            }
        }
    }
    
    // ✅ (3) Preload avec contrôle du lifecycle
    public func startStandardPreload() {
        // Annule toute tâche de preload précédente
        activePreloadTask?.cancel()
        
        activePreloadTask = Task { [weak self] in
            guard let self = self else { return }
            await self.preloadFeatures(priority: .standard)
        }
    }
    
    // MARK: - Lifecycle Management
    
    public func cancelAllPendingTasks() {
        for task in pendingTasks.values {
            task.cancel()
        }
        pendingTasks.removeAll()
    }
    
    public func cancelLoading<F: FeatureLoadable>(_ type: F.Type) {
        let key = ObjectIdentifier(type)
        pendingTasks[key]?.cancel()
        pendingTasks[key] = nil
    }
    
    // ✅ (3) Arrêt propre du preload
    public func stopStandardPreload() {
        activePreloadTask?.cancel()
        activePreloadTask = nil
    }
    
    // MARK: - Helpers
    
    public func isLoaded<F: FeatureLoadable>(_ type: F.Type) -> Bool {
        loadedFeatures[ObjectIdentifier(type)] != nil
    }
    
    public func isRegistered<F: FeatureLoadable>(_ type: F.Type) -> Bool {
        dependencyProviders[ObjectIdentifier(type)] != nil
    }
    
    public func isLoading<F: FeatureLoadable>(_ type: F.Type) -> Bool {
        pendingTasks[ObjectIdentifier(type)] != nil
    }
    
    public func unload<F: FeatureLoadable>(_ type: F.Type) {
        let key = ObjectIdentifier(type)
        pendingTasks[key]?.cancel()
        loadedFeatures[key] = nil
        pendingTasks[key] = nil
    }
    
    public func unloadAll() {
        cancelAllPendingTasks()
        // ✅ (3) Arrêter aussi le preload
        stopStandardPreload()
        loadedFeatures.removeAll()
    }
    
    public func resetAll() {
        cancelAllPendingTasks()
        stopStandardPreload()
        loadedFeatures.removeAll()
        dependencyProviders.removeAll()
        priorities.removeAll()
        preloaders.removeAll()
    }
}
