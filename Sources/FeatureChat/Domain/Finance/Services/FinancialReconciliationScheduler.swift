//
//  FinancialReconciliationScheduler.swift
//  FeatureChat
//
//  Déclenchement de la réconciliation — tâches 8.3 et 8.5.
//
//  Voir BLOC1-CHAT-FINANCE-INTEGRATION.md §7 et §8.

import Foundation
import WaanguCoreKit

/// Décide *quand* réconcilier.
///
/// Séparé de `FinancialObjectUseCases`, qui sait *comment*. La distinction
/// compte : le « quand » a trois déclencheurs indépendants — retour du réseau,
/// ancienneté d'un état ambigu, retour au premier plan — et les mêler à la
/// logique de lecture rendrait chacun difficile à tester isolément.
///
/// Ne réconcilie jamais en boucle serrée : un objet qui reste `unknown` ne doit
/// pas produire une requête par seconde, sinon un incident backend se transforme
/// en tempête de requêtes venue de tous les clients à la fois.
public actor FinancialReconciliationScheduler {

    private let useCases: any FinancialObjectUseCasesProtocol
    private let logger: any AppLoggerProtocol

    /// Délai minimal avant de reprendre un objet ambigu.
    ///
    /// Deux minutes : assez court pour qu'un utilisateur qui regarde sa carte
    /// voie l'état se résoudre, assez long pour ne pas marteler un backend en
    /// difficulté.
    private let ambiguityGracePeriod: TimeInterval

    /// Dernière réconciliation effectuée, pour ne pas en enchaîner deux.
    private var lastRun: Date?

    /// Intervalle minimal entre deux passes, tous déclencheurs confondus.
    private let minimumInterval: TimeInterval = 30

    public init(
        useCases: any FinancialObjectUseCasesProtocol,
        logger: any AppLoggerProtocol,
        ambiguityGracePeriod: TimeInterval = 120
    ) {
        self.useCases = useCases
        self.logger = logger
        self.ambiguityGracePeriod = ambiguityGracePeriod
    }

    // MARK: - Déclencheurs

    /// Le réseau est revenu — tâche 8.3.
    ///
    /// Tout objet non final est revalidé. Un devis expiré passera à `expired` au
    /// retour serveur et imposera un parcours complet : c'est voulu, une reprise
    /// silencieuse sur un devis périmé exécuterait l'opération à un taux qui
    /// n'est plus le bon.
    public func networkDidBecomeAvailable() async {
        await run(trigger: "network_available", force: true)
    }

    /// L'application revient au premier plan.
    public func applicationDidBecomeActive() async {
        await run(trigger: "foreground", force: false)
    }

    /// Passe périodique — tâche 8.5.
    ///
    /// Ne reprend que les objets ambigus depuis plus que le délai de grâce. Un
    /// objet qui vient de passer en `unknown` a peut-être une réponse serveur en
    /// vol ; le requêter immédiatement doublerait la charge sans rien apprendre.
    public func periodicSweep() async {
        await run(trigger: "periodic", force: false)
    }

    /// Changement de compte ou de pays : l'état précédent ne s'applique plus.
    public func reset() {
        lastRun = nil
    }

    /// Nombre de passes réellement exécutées. Pour les tests et l'observabilité.
    public private(set) var runCount = 0

    // MARK: - Exécution

    private func run(trigger: String, force: Bool) async {
        if !force, let lastRun, Date().timeIntervalSince(lastRun) < minimumInterval {
            // Trop tôt. Ne pas journaliser : ce chemin est fréquent et le bruit
            // masquerait les passes réelles.
            return
        }

        // Les objets relus du disque et encore sans réponse serveur — un
        // lancement hors réseau — ne sont pas dans le magasin, donc pas parmi
        // les candidats. Sans cette reprise, une opération tuée en vol puis
        // relancée sans réseau n'était plus requêtée avant le lancement suivant.
        // Sans effet quand il n'en reste aucun.
        await useCases.restoreHydrated()

        let candidates = await useCases.pendingReconciliation()

        // Le retour du réseau reprend tout : l'état affiché date d'avant la
        // coupure, quelle que soit son ancienneté. Une passe ordinaire, elle,
        // respecte le délai de grâce — un objet qui vient de basculer en
        // `unknown` a peut-être une réponse serveur en vol, et le requêter
        // aussitôt doublerait la charge sans rien apprendre.
        let due = force ? candidates : candidates.filter { isEligibleForSweep($0) }

        // Rien à reprendre : ne pas horodater la passe et ne pas journaliser.
        // Marquer `lastRun` ici ferait taire la passe suivante, qui aurait
        // peut-être, elle, quelque chose à faire.
        guard !due.isEmpty else { return }

        lastRun = Date()
        runCount += 1
        await logger.log(
            "Réconciliation financière (\(trigger)) — \(due.count) objet(s)",
            level: .info
        )

        for payload in due {
            _ = await useCases.refresh(payload.reference)
        }
    }

    /// `true` si cet objet est ambigu depuis assez longtemps pour être repris.
    ///
    /// Exposé pour que la décision soit testable sans horloge réelle.
    public nonisolated func isEligibleForSweep(
        _ payload: FinancialCardPayload,
        now: Date = Date()
    ) -> Bool {
        guard payload.needsReconciliation else { return false }
        return now.timeIntervalSince(payload.lastRefreshedAt) >= ambiguityGracePeriod
    }
}
