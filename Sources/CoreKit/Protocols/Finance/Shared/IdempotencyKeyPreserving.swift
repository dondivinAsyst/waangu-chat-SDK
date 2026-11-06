//
//  IdempotencyKeyPreserving.swift
//  CoreKit
//
//  Garantit qu'un retry porte la clé de sa première tentative.
//
//  Voir BLOC1-CHAT-FINANCE-INTEGRATION.md §3.3.

import Foundation

/// Gardien de la clé d'idempotence d'une opération.
///
/// Le rôle tient en une règle : **une opération, une clé, pour toujours**.
/// Toute tentative de rejouer une opération avec une clé différente est une erreur
/// de programmation qui produit un double débit, et doit donc lever plutôt que
/// s'exécuter.
///
/// Ce contrat existe parce que la discipline seule ne suffit pas : une clé peut se
/// perdre à un kill d'application, à une reconstruction de view model, ou dans un
/// chemin de retry écrit six mois plus tard par quelqu'un d'autre. L'implémentation
/// doit persister — une mémoire volatile ne protège pas du cas principal.
public protocol IdempotencyKeyPreserving: Sendable {

    /// Enregistre le contexte d'une opération qui démarre.
    ///
    /// - Throws: si `operationID` est déjà enregistré avec une autre clé. Un
    ///   réenregistrement silencieux effacerait la clé d'origine — exactement ce
    ///   que ce contrat empêche.
    func register(operationID: String, context: IdempotencyContext) async throws

    /// Restitue le contexte à réutiliser pour la tentative suivante.
    ///
    /// - Returns: `nil` si l'opération est inconnue. L'appelant crée alors un
    ///   contexte neuf — mais uniquement s'il est certain qu'aucune tentative n'a
    ///   déjà été soumise.
    func context(for operationID: String) async -> IdempotencyContext?

    /// Vérifie qu'une tentative porte bien la clé d'origine.
    ///
    /// - Throws: `IdempotencyViolation.keyMismatch` si la clé diverge.
    func assertSameKey(operationID: String, providedKey: String) async throws

    /// Oublie toutes les clés d'un compte.
    ///
    /// À appeler à la déconnexion, avec l'identifiant porté par l'événement de
    /// logout — jamais avec « l'utilisateur courant », qui peut déjà avoir été
    /// effacé de la session au moment où l'abonné réagit.
    ///
    /// Sans cela, les clés survivent dans le trousseau, qui n'est pas vidé par
    /// une déconnexion : l'identifiant d'opération du compte suivant entre alors
    /// en collision avec celui du précédent.
    func purge(userID: String) async

    /// Clôt une opération parvenue à un état final.
    ///
    /// À n'appeler que sur un état **réellement** final. Une opération en
    /// `unknown` n'est pas terminée : libérer sa clé autoriserait une nouvelle
    /// tentative sous une clé neuve, donc un second débit.
    func release(operationID: String) async
}

// MARK: - IdempotencyViolation

public enum IdempotencyViolation: Error, Sendable, Equatable {

    /// Aucun registre de clés n'est branché.
    ///
    /// **Bloque l'opération** au lieu de la laisser partir sans protection :
    /// une écriture financière sans clé préservée est une écriture qu'un
    /// réessai peut dupliquer.
    case preserverUnavailable


    /// Un retry porte une clé différente de celle de la première tentative.
    /// Défaut de programmation, pas condition d'exécution : à corriger, pas à rattraper.
    case keyMismatch(operationID: String)

    /// Opération déjà enregistrée sous une autre clé.
    case alreadyRegistered(operationID: String)

    /// La clé dépasse la fenêtre de rétention backend : le rejeu n'est plus garanti
    /// idempotent. L'opération doit être relue, pas retentée.
    case keyExpired(operationID: String)
}

// MARK: - Défaut fermé

/// Ne préserve aucune clé, et **empêche toute opération de démarrer**.
///
/// Remplace le `nil` qui servait de valeur par défaut. La différence est
/// exactement celle qui sépare un garde-fou d'un trou : avec `nil`, chaque
/// `preserver?.assertSameKey(...)` devenait une instruction vide, et une
/// tentative rejouée avec un contenu différent passait sans contrôle. Le
/// chaînage optionnel ne signale rien — il n'y a même pas d'avertissement de
/// compilation à ignorer.
///
/// Ici, `register` échoue, donc l'opération n'atteint jamais le réseau. Une
/// application non câblée ne paie pas ; elle ne paie pas *deux fois* non plus.
public struct ClosedIdempotencyKeyPreserver: IdempotencyKeyPreserving {

    public init() {}

    /// Refuse d'enregistrer, donc refuse de laisser démarrer.
    public func register(operationID: String, context: IdempotencyContext) async throws {
        throw IdempotencyViolation.preserverUnavailable
    }

    /// Aucune opération n'est connue — cohérent avec un registre qui n'a jamais
    /// rien accepté.
    public func context(for operationID: String) async -> IdempotencyContext? { nil }

    /// Refuse plutôt que d'acquiescer.
    ///
    /// Acquiescer serait le pire des deux mondes : la vérification passerait
    /// sans rien vérifier, et l'appelant croirait la clé validée.
    public func assertSameKey(operationID: String, providedKey: String) async throws {
        throw IdempotencyViolation.preserverUnavailable
    }

    /// Rien à purger.
    public func purge(userID: String) async {}

    /// Rien à libérer : aucune opération n'a jamais été enregistrée.
    public func release(operationID: String) async {}
}
