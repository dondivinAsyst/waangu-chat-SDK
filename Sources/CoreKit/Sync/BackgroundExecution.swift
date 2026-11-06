//
//  BackgroundExecution.swift
//  CoreKit
//
//  Tâches de fond — Bloc 8, §20.
//
//  Ferme P0-2. `BackgroundPolicyManager` contenait le seul appel à
//  `BGTaskScheduler.register` du dépôt et n'avait aucun appelant ; son
//  gestionnaire ne faisait rien et ne replanifiait pas.
//

import Foundation

/// Ce dont dispose une exécution de fond.
///
/// iOS accorde quelques dizaines de secondes, révocables à tout moment. Une
/// tâche qui ignore ces bornes est tuée au milieu de son travail — et sur un
/// chemin de synchronisation, « au milieu » veut dire un état partiel.
public struct BackgroundBudget: Sendable {

    /// Échéance au-delà de laquelle le système reprend la main.
    public let deadline: Date

    /// Le réseau est disponible.
    public let hasNetwork: Bool

    /// Mode économie d'énergie actif.
    public let isLowPower: Bool

    /// Économiseur de données actif.
    public let isConstrainedNetwork: Bool

    public init(deadline: Date, hasNetwork: Bool,
                isLowPower: Bool = false, isConstrainedNetwork: Bool = false) {
        self.deadline = deadline
        self.hasNetwork = hasNetwork
        self.isLowPower = isLowPower
        self.isConstrainedNetwork = isConstrainedNetwork
    }

    public func remaining(now: Date = Date()) -> TimeInterval {
        max(0, deadline.timeIntervalSince(now))
    }

    /// Reste-t-il de quoi tenter une unité de travail ?
    ///
    /// Interrogé **avant** chaque unité et non seulement au début : commencer
    /// une page de synchronisation avec deux secondes devant soi produit une
    /// transaction avortée.
    public func permitsMoreWork(estimated: TimeInterval, now: Date = Date()) -> Bool {
        remaining(now: now) > estimated
    }

    /// Ce qu'une tâche de fond n'a **jamais** le droit de faire.
    ///
    /// Le §20 le pose en une phrase : aucune tâche de fond ne doit exécuter
    /// silencieusement une mutation financière. Ce n'est pas une question de
    /// budget mais de consentement — une confirmation de paiement exige un
    /// utilisateur devant l'écran, et il n'y en a pas ici.
    public var permitsFinancialMutation: Bool { false }
}

/// Ce qu'a donné une exécution de fond.
public enum BackgroundOutcome: String, Sendable, Equatable {

    /// Travail terminé.
    case completed = "COMPLETED"

    /// Avancé, pas terminé. Reprendra au prochain réveil, depuis le curseur
    /// committé — pas depuis le début.
    case partial   = "PARTIAL"

    /// Le système a repris la main avant la fin.
    case expired   = "EXPIRED"

    /// Rien à faire, ou conditions non réunies (pas de réseau).
    case skipped   = "SKIPPED"

    /// Déjà en cours — un second réveil n'en lance pas un second.
    case alreadyRunning = "ALREADY_RUNNING"

    /// Ce que rendre à `setTaskCompleted(success:)`.
    ///
    /// `partial` compte comme un succès : la tâche a fait ce qu'elle pouvait
    /// dans le temps imparti. Rapporter un échec ferait baisser la priorité que
    /// le système accorde aux réveils suivants, punissant une exécution
    /// correcte.
    public var isSuccess: Bool {
        self != .expired
    }
}

/// Reçoit le travail de fond de l'application.
///
/// Le gestionnaire `BGAppRefreshTask` vit dans `RealtimeTransportKit`, qui ne
/// connaît pas le conteneur d'injection de l'application — d'où le commentaire
/// « accès au DependencyContainer via une singleton ou injection » laissé dans
/// le code, et le gestionnaire vide qui allait avec. Ce coordinateur est le
/// point de rendez-vous : l'app dépose le travail au lancement, le transport
/// l'exécute au réveil.
public actor BackgroundRefreshCoordinator {

    public static let shared = BackgroundRefreshCoordinator()

    private var work: (@Sendable (BackgroundBudget) async -> BackgroundOutcome)?
    private var isRunning = false
    private var lastOutcome: BackgroundOutcome?
    private var lastRunAt: Date?

    private init() {}

    /// Dépose le travail à exécuter au réveil. Appelé une fois, au lancement.
    public func setWork(_ work: @escaping @Sendable (BackgroundBudget) async -> BackgroundOutcome) {
        self.work = work
    }

    /// Exécute le travail, si les conditions le permettent.
    ///
    /// Idempotent par réentrance : deux réveils concurrents — un
    /// `BGAppRefreshTask` et un push silencieux, par exemple — ne lancent pas
    /// deux synchronisations sur la même base.
    public func run(budget: BackgroundBudget) async -> BackgroundOutcome {

        guard !isRunning else { return .alreadyRunning }
        guard let work else { return .skipped }
        guard budget.hasNetwork else { return .skipped }

        isRunning = true
        defer { isRunning = false }

        let outcome = await work(budget)
        lastOutcome = outcome
        lastRunAt = Date()
        return outcome
    }

    /// Diagnostic (§26) — sans donnée métier.
    public func diagnostics() -> (lastOutcome: BackgroundOutcome?, lastRunAt: Date?, isRunning: Bool) {
        (lastOutcome, lastRunAt, isRunning)
    }
}
