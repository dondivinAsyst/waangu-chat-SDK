//
//  SQLiteTransactionScope.swift
//  StorageKit
//
//  B51 — à qui appartient une transaction SQLite ouverte.
//

import Foundation

/// Jeton de la transaction que la tâche courante a ouverte.
///
/// `DatabaseStore.withTransaction` le pose autour de son bloc. Le moteur ne
/// laisse passer, pendant qu'une transaction est ouverte sur un namespace, que
/// les opérations portant ce jeton — le bloc et les tâches enfants qu'il crée.
/// Les autres attendent la fin de la transaction : sans cela, une écriture d'une
/// autre tâche entrerait dans la transaction et serait annulée avec elle, et une
/// lecture verrait des données pas encore validées.
enum SQLiteTransactionScope {
    @TaskLocal static var token: UUID?
}
