//
//  CurrentAccountReader.swift
//  StorageKit
//
//  Lecture `Sendable` de l'identifiant du compte courant.
//

import Foundation

/// Donne l'identifiant du compte courant à du code isolé par acteur.
///
/// `AppSettingsProtocol` ne convient pas ici : c'est un `AnyObject` mutable, donc
/// non `Sendable`, et le capturer dans une fermeture `@Sendable` ne compile pas.
/// Recopier la clé `UserDefaults` côté appelant ne convient pas non plus — elle
/// est interne à StorageKit, et un littéral dupliqué se désynchronise en silence
/// le jour où la clé change.
///
/// Ce lecteur existe donc pour un seul usage : permettre à un composant isolé —
/// le gardien des clés d'idempotence — de savoir à quel compte il travaille, sans
/// figer cette valeur à la construction. Le compte change en cours de processus.
public struct CurrentAccountReader: Sendable {

    private let store: any PreferenceStoreProtocol

    public init(store: any PreferenceStoreProtocol) {
        self.store = store
    }

    /// Identifiant du compte courant, ou `nil` hors session.
    ///
    /// Relu à chaque appel, jamais mis en cache : une valeur mémorisée
    /// ferait travailler le compte suivant dans l'espace de noms du précédent.
    public var userID: String? {
        let value = store.string(forKey: UserDefaultsKeys.Session.currentUserId)
        return (value?.isEmpty ?? true) ? nil : value
    }
}
