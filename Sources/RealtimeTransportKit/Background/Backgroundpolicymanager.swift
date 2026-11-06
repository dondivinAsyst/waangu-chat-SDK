//
//  Backgroundpolicymanager.swift
//  AppModules
//
//  Created by Asyst on 6/4/26.
//

// MARK: - RealtimeKit/Background/BackgroundPolicyManager.swift
//
// Module  : RealtimeKit (internal)
// Rôle    : Gère l'exécution en background iOS selon la TopicBackgroundPolicy
//           de chaque souscription déclarée dans RealtimeRegistrable.
//
//           Sur iOS, l'app est suspendue ~30 secondes après le passage
//           en background. Sans gestion explicite, toutes les connexions
//           temps réel meurent. Ce manager applique les politiques :
//
//   .disconnect      → annuler la souscription immédiatement
//   .maintainBriefly → UIApplication.beginBackgroundTask (~30s)
//   .keepAlive       → BGAppRefreshTask (scheduling périodique iOS)
//   .reducedFrequency→ throttle le transport pendant le background

import Foundation
import WaanguCoreKit
#if canImport(UIKit)
import UIKit
import BackgroundTasks
#endif

// MARK: - BackgroundPolicyManager

/// Applique les politiques de background de chaque souscription.
public actor BackgroundPolicyManager {

    // MARK: - Dependencies

    private let registrations: [TopicRegistration]
    private let realtimeClient: any RealtimeClientProtocol

    // MARK: - State

    /// Tasks UIKit de background en cours (beginBackgroundTask).
    private var backgroundTaskIds: [String: UIBackgroundTaskIdentifier] = [:]

    // MARK: - BGTask Identifier

    static let bgRefreshIdentifier = "com.waangu.realtime.refresh"

    // MARK: - Init

    init(
        registrations: [TopicRegistration],
        realtimeClient: any RealtimeClientProtocol
    ) {
        self.registrations = registrations
        self.realtimeClient = realtimeClient
    }

    // MARK: - App Lifecycle

    /// Appelé quand l'app passe en background.
    ///
    /// Applique la politique de chaque topic enregistré :
    /// - `.disconnect`      → cancel la souscription
    /// - `.maintainBriefly` → démarre un background task UIKit
    /// - `.keepAlive`       → schedule un BGAppRefreshTask
    /// - `.reducedFrequency`→ réduit la fréquence du heartbeat
    func handleDidEnterBackground() async {
        for registration in registrations {
            await apply(
                policy: registration.backgroundPolicy,
                for: registration
            )
        }
    }

    /// Appelé quand l'app revient en foreground.
    ///
    /// Arrête les background tasks UIKit et restaure les souscriptions
    /// qui avaient été annulées.
    func handleWillEnterForeground() async {
        // Terminer tous les background tasks UIKit.
        for (key, taskId) in backgroundTaskIds {
            endBackgroundTask(taskId, for: key)
        }
        backgroundTaskIds.removeAll()

        // Restaurer les souscriptions des features qui ont .disconnect.
        // Note : le RealtimeClient re-souscrit automatiquement après reconnexion.
        // Les features qui observent le connectionState géreront ça.
    }

    // MARK: - BGAppRefreshTask Registration

    /// Enregistre le BGAppRefreshTask au lancement de l'app.
    ///
    /// À appeler dans AppDelegate.didFinishLaunchingWithOptions.
    ///
    /// `public` depuis le Bloc 8 : l'`AppDelegate` doit pouvoir l'appeler, et
    /// c'est la seule raison pour laquelle ce type sort du module.
    public static func registerBackgroundTasks() {
        #if canImport(BackgroundTasks)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: bgRefreshIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            Self.handleBackgroundRefresh(task: refreshTask)
        }
        #endif
    }

    // MARK: - Private — Policy Application

    private func apply(
        policy: TopicBackgroundPolicy,
        for registration: TopicRegistration
    ) async {
        let topicKey = registration.topicPattern.path

        switch policy {

        case .disconnect:
            // Annuler les souscriptions de cette feature.
            if let feature = registration.topicPattern.feature {
                await realtimeClient.cancelAllSubscriptions(forFeature: feature.rawValue)
            }

        case .maintainBriefly:
            // beginBackgroundTask → ~30 secondes supplémentaires.
            let taskId = beginBackgroundTask(for: topicKey)
            backgroundTaskIds[topicKey] = taskId

        case .keepAlive:
            // Scheduler un BGAppRefreshTask pour maintien périodique.
            scheduleBackgroundRefresh()

        case .reducedFrequency(let factor):
            // Le transport réduit son activité — géré par BatteryAwareScheduler.
            #if DEBUG
            print("[RealtimeKit] Background: reducing frequency ÷\(factor) for \(topicKey)")
            #endif
        }
    }

    // MARK: - Private — UIKit Background Task

    private func beginBackgroundTask(for key: String) -> UIBackgroundTaskIdentifier {
        #if canImport(UIKit)
        var taskId = UIBackgroundTaskIdentifier.invalid
        taskId = UIApplication.shared.beginBackgroundTask(withName: "realtime.\(key)") {
            // Expiry handler — iOS va suspendre l'app dans quelques secondes.
            Task {
                await self.endBackgroundTask(taskId, for: key)
            }
        }
        return taskId
        #else
        return UIBackgroundTaskIdentifier.invalid
        #endif
    }

    private func endBackgroundTask(
        _ taskId: UIBackgroundTaskIdentifier,
        for key: String
    ) {
        #if canImport(UIKit)
        guard taskId != .invalid else { return }
        UIApplication.shared.endBackgroundTask(taskId)
        backgroundTaskIds.removeValue(forKey: key)
        #endif
    }

    // MARK: - Private — BGAppRefreshTask

    private func scheduleBackgroundRefresh() {
        #if canImport(BackgroundTasks)
        let request = BGAppRefreshTaskRequest(
            identifier: Self.bgRefreshIdentifier
        )
        // iOS garantit l'exécution approximativement toutes les 15 minutes.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        try? BGTaskScheduler.shared.submit(request)
        #endif
    }

    private static func handleBackgroundRefresh(task: BGAppRefreshTask) {

        // Replanifier **en premier**. Si l'exécution échoue ou expire, un
        // réveil est déjà demandé ; replanifier à la fin ne s'exécuterait pas
        // en cas d'expiration, et la chaîne de réveils s'arrêterait pour de bon.
        scheduleNextRefresh()

        // Le système accorde ~30 s. On garde une marge : dépasser fait tuer le
        // processus, ce qui laisse une transaction ouverte.
        let budget = BackgroundBudget(
            deadline: Date(timeIntervalSinceNow: 25),
            hasNetwork: true,
            isLowPower: ProcessInfo.processInfo.isLowPowerModeEnabled
        )

        let work = Task {
            let outcome = await BackgroundRefreshCoordinator.shared.run(budget: budget)
            task.setTaskCompleted(success: outcome.isSuccess)
        }

        // L'expiration arrive sans préavis. Annuler la tâche laisse le travail
        // s'arrêter à sa prochaine borne de coopération plutôt qu'au milieu
        // d'une écriture.
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    /// Redemande un réveil. Séparé de ``scheduleBackgroundRefresh`` pour être
    /// appelable depuis le contexte statique du gestionnaire.
    private static func scheduleNextRefresh() {
        #if canImport(BackgroundTasks)
        let request = BGAppRefreshTaskRequest(identifier: bgRefreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
        #endif
    }
}
