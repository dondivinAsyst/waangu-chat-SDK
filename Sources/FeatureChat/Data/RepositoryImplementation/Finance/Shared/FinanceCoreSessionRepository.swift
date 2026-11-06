//
//  FinanceCoreSessionRepository.swift
//  FeatureChat
//
//  Amorçage de session Chat Core — INTEGRATION_CHAT_FINANCE.md §1.1.
//

import Foundation
import WaanguCoreKit

/// Tient l'instantané d'amorçage et le Hub, les recharge quand ils expirent.
///
/// Ordre imposé par le contrat :
///
/// ```
/// 1. GET  /chat-core/experience/config
/// 2. GET  /chat-core/governance/capabilities
/// 3. GET  /chat-core/security/capabilities
/// 4. GET  /chat-core/financial/session/resume
/// 5. si locked → POST /chat-core/financial/session/resume
/// 6. GET  /chat-core/financial/hub/actions?conversationType=…
/// ```
///
/// Acteur, et les amorçages concurrents partagent **une** résolution : chaque
/// écran qui s'ouvre en même temps ne relance pas six requêtes.
actor FinanceCoreSessionRepository {

    private let dataSource: any RemoteChatFinanceDataSourceProtocol
    private let deviceID: @Sendable () -> String
    private let now: @Sendable () -> Date
    /// §1.1 — ce que la négociation dit de l'appareil. `nil` ⇒ non envoyé.
    private let networkMonitor: (any NetworkMonitoringProtocol)?
    private let reducedMotionPreferred: @Sendable () async -> Bool?

    private var snapshot: FinanceSessionSnapshot?
    private var pending: Task<Result<FinanceSessionSnapshot, FinanceCoreError>, Never>?
    private var hubCache: [String: (hash: String?, actions: [ResolvedActionDTO])] = [:]
    private var selfFolder: SelfConversationDTO?

    init(dataSource: any RemoteChatFinanceDataSourceProtocol,
         deviceID: @escaping @Sendable () -> String,
         now: @escaping @Sendable () -> Date = Date.init,
         networkMonitor: (any NetworkMonitoringProtocol)? = nil,
         reducedMotionPreferred: @escaping @Sendable () async -> Bool? = { nil }) {
        self.dataSource = dataSource
        self.deviceID = deviceID
        self.now = now
        self.networkMonitor = networkMonitor
        self.reducedMotionPreferred = reducedMotionPreferred
    }

    // MARK: - Instantané

    /// L'instantané courant, rechargé s'il est absent ou expiré.
    func current() async -> Result<FinanceSessionSnapshot, FinanceCoreError> {
        if let snapshot, FinanceGovernanceMapper.expiry(of: snapshot) > now() {
            return .success(snapshot)
        }
        return await bootstrap()
    }

    /// Relance l'amorçage. Les appels concurrents attendent la même résolution.
    func bootstrap() async -> Result<FinanceSessionSnapshot, FinanceCoreError> {
        if let pending { return await pending.value }
        let task = Task { await self.performBootstrap() }
        pending = task
        let result = await task.value
        pending = nil
        if case .success(let fresh) = result {
            // Configuration serveur changée : le Hub en cache ne vaut plus. Les
            // deux empreintes comptent — experience (§1.2) et gouvernance (§1.3).
            if fresh.governance.configHash != snapshot?.governance.configHash
                || fresh.experience.configHash != snapshot?.experience.configHash {
                hubCache.removeAll()
            }
            snapshot = fresh
        }
        return result
    }

    /// Ce que la session permet, ou `nil` si l'amorçage n'a pas abouti.
    ///
    /// `nil` se lit **refusé** : un droit que le serveur n'a pas pu affirmer
    /// n'est pas un droit.
    func status() async -> FinanceSessionStatus? {
        guard case .success(let snapshot) = await current() else { return nil }
        return FinanceGovernanceMapper.status(from: snapshot)
    }

    /// Le pays de la session, tel que `/experience/config` le rend — celui du
    /// JWT. `nil` si l'amorçage n'a pas abouti : l'app ne le devine jamais.
    func country() async -> String? {
        guard case .success(let snapshot) = await current() else { return nil }
        return snapshot.experience.country
    }

    /// Le serveur accorde-t-il ce droit de session (`GET /security/capabilities`) ?
    func securityAllows(_ right: String) async -> Bool {
        guard case .success(let snapshot) = await current() else { return false }
        return snapshot.security.allows(right)
    }

    /// Oublie tout — déconnexion, changement de compte, révocation.
    func invalidate() {
        snapshot = nil
        hubCache.removeAll()
        selfFolder = nil
        FinanceMembershipEpochs.shared.clear()
    }

    // MARK: - Dossier personnel (§5.1.1)

    /// Le dossier « Mes factures » — un membre, pas de 1-1.
    ///
    /// Mémorisé : c'est le même dossier pour toute la session, et chaque écran
    /// ouvert depuis les Réglages le redemanderait sinon. Il ne se recrée pas
    /// côté serveur — Core réutilise celui qui existe.
    func selfConversation() async -> Result<SelfConversationDTO, FinanceCoreError> {
        if let selfFolder { return .success(selfFolder) }
        let result = await FinanceCoreError.capture {
            try await dataSource.selfConversation()
        }
        if case .success(let folder) = result { selfFolder = folder }
        return result
    }

    // MARK: - Hub

    func hubActions(conversationType: String) async -> Result<[ResolvedActionDTO], FinanceCoreError> {
        let session = await current()
        guard case .success(let snapshot) = session else {
            return session.map { _ in [] }
        }
        let hash = snapshot.governance.configHash
        if let cached = hubCache[conversationType], cached.hash == hash {
            return .success(cached.actions)
        }
        let result = await FinanceCoreError.capture {
            try await dataSource.hubActions(conversationType: conversationType)
        }
        if case .success(let actions) = result {
            hubCache[conversationType] = (hash, actions)
        }
        return result
    }

    // MARK: - §1.1 Négociation

    /// `POST /client-capabilities/negotiate` — optionnel, à la place que lui
    /// donne le §1.1 : juste après experience, avant la gouvernance.
    ///
    /// Un échec ne fait jamais échouer l'amorçage : la réponse n'est pas
    /// publiée, rien n'en dépend. Seul ce que l'appareil sait de lui-même part ;
    /// `networkQuality` reste absent (voir `NegotiateClientCapabilitiesRequest`).
    private func negotiate() async {
        let request = NegotiateClientCapabilitiesRequest(
            platform: "IOS",
            appVersion: Bundle.main.versionNumber,
            lowData: await networkMonitor?.currentSnapshot().isConstrained,
            reducedMotionPreferred: await reducedMotionPreferred())
        do {
            try await dataSource.negotiateClientCapabilities(request)
        } catch {
            #if DEBUG
            print("[FinanceSession] negotiate skipped: \(error)")
            #endif
        }
    }

    // MARK: - Séquence

    private func performBootstrap() async -> Result<FinanceSessionSnapshot, FinanceCoreError> {
        let experience: ExperienceConfigDTO
        switch await FinanceCoreError.capture({ try await dataSource.experienceConfig() }) {
        case .success(let value): experience = value
        case .failure(let error): return .failure(error)
        }
        await negotiate()

        let governance: GovernanceSnapshotDTO
        switch await FinanceCoreError.capture({ try await dataSource.governanceCapabilities() }) {
        case .success(let value): governance = value
        case .failure(let error): return .failure(error)
        }

        let security: SecurityCapabilitiesDTO
        switch await FinanceCoreError.capture({ try await dataSource.securityCapabilities() }) {
        case .success(let value): security = value
        case .failure(let error): return .failure(error)
        }

        // La reprise ne fait pas échouer l'amorçage : sans elle, la lecture reste
        // possible et l'écriture reste verrouillée (`resume == nil`).
        var resume = try? await dataSource.sessionResumeState()
        var currentExperience = experience
        var currentSecurity = security

        if resume?.locked ?? true {
            // Les quatre affirmations du §1.6 : l'amorçage qui précède vient de
            // relire experience, gouvernance et sécurité pour ce compte.
            let request = ResumeSessionRequest.afterBootstrap(deviceID: deviceID())
            if let resumed = try? await dataSource.resumeSession(request) {
                resume = resumed
                // Experience **et** sécurité ont été lues avant la reprise : les
                // deux portent le verrou que la reprise vient de lever, et les
                // garder telles quelles rendrait l'écriture refusée par un fait
                // périmé. C'est ce qui affichait « session à revalider » juste
                // après un « Financial actions unlocked » du serveur : la
                // sécurité annonçait encore `financialActionsLocked` et
                // `PAYMENT_PREPARE: DENY`.
                if resumed.locked == false {
                    if let refreshed = try? await dataSource.experienceConfig() {
                        currentExperience = refreshed
                    }
                    if let refreshed = try? await dataSource.securityCapabilities() {
                        currentSecurity = refreshed
                    }
                }
            }
        }

        return .success(FinanceSessionSnapshot(
            experience: currentExperience, governance: governance,
            security: currentSecurity, resume: resume, fetchedAt: now()
        ))
    }
}
