//
//  LogDestination.swift
//  AppModules
//
//  Created by Asyst on 3/23/26.
//
// Destinations de log disponibles.
// Utilisé par AppLogger pour router les messages.
// `.remote` est intentionnellement séparé de Sentry —
// AppLogger ne connaît pas Sentry. C'est ObservabilityKit qui écoute
// les logs via un provider injecté.

import Foundation

public enum LogDestination: Sendable {

    /// Console Xcode + Console.app via os.Logger (OSLog).
    case console

    /// Fichier local sur le device (debug avancé, support).
    case file

    /// Service distant (Sentry, Datadog...) — géré par ObservabilityKit.
    case remote

    /// Toutes les destinations simultanément.
    case all

    /// Destination par défaut selon le build.
    /// - DEBUG : console uniquement
    /// - RELEASE : console + remote (Sentry via ObservabilityKit)
    public static var `default`: LogDestination {
        #if DEBUG
        return .console
        #else
        return .all
        #endif
    }
}
