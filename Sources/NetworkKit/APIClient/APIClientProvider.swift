// MARK: - NetworkKit/APIClient/APIClientProvider.swift
//
// Provider singleton d'APIClient avec coalescing des appels concurrents.
// Garantit qu'une seule instance d'APIClient est créée par session.

import Foundation
import WaanguCoreKit

enum APIClientError: Error, LocalizedError {
    case providerDeallocated
    case configurationResolutionFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .providerDeallocated:
            return "APIClientProvider a été désalloué avant la fin de la création du client."
        case .configurationResolutionFailed(let e):
            return "Échec de la résolution de la configuration : \(e.localizedDescription)"
        }
    }
}

public actor APIClientProvider {

    private var client: (any APIClientProtocol)?
    private var clientTask: Task<any APIClientProtocol, Error>?

    public init() {}

    public func getOrCreate(
        baseURL : String,
        appConfiguration: any AppConfigurationProviding,
        logger: AppLogger,
        performanceMonitor: any PerformanceMonitorProtocol,
        networkMonitor: any NetworkMonitoringProtocol,
        deviceInfoProvider: any DeviceInfoProvidingProtocol,
        tokenManager: any TokenManagerProtocol,
        basicAuthToken: String? = nil
    ) async throws -> any APIClientProtocol {

//        if let client { return client }
        if let task = clientTask { return try await task.value }

        let task = Task<any APIClientProtocol, Error> { [weak self] in
            guard let self else { throw APIClientError.providerDeallocated }
            let factory = APIClientFactory(
                baseURL:baseURL,
                appConfiguration: appConfiguration,
                logger: logger,
                performanceMonitor: performanceMonitor,
                networkMonitor: networkMonitor,
                deviceInfoProvider: deviceInfoProvider,
                tokenManager: tokenManager,
                basicAuthToken: basicAuthToken
            )
            let newClient = try await factory.make()
            await self.finalize(client: newClient)
            return newClient
        }

        clientTask = task

        do {
            let result = try await task.value
            return result
        } catch {
            clientTask = nil
            throw error
        }
    }

    public func reset() {
        client = nil
        clientTask?.cancel()
        clientTask = nil
    }

    private func finalize(client: any APIClientProtocol) {
        self.client = client
        self.clientTask = nil
    }
}
