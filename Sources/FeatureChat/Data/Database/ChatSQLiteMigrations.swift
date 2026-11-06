//
//  ChatSQLiteMigrations.swift
//  FeatureChat
//
//  SQLite migrations for the chat GRDB schema.
//

import WaanguCoreKit


enum ChatMigrations {

    static var all: [any MigrationStep] {
        [
            // v2 → v3 : nouveaux champs sur ContactModel
//            FieldMigration(from: 2, to: 3, entity: ContactModel.self, field: "isTitle",     defaultValue: "0"),
//            FieldMigration(from: 2, to: 3, entity: ContactModel.self, field: "name"),
//            FieldMigration(from: 2, to: 3, entity: ContactModel.self, field: "contactName"),
//
//            // v3 → v4 : nouveau champ sur GroupPermissionsModel
//            FieldMigration(from: 3, to: 4, entity: GroupPermissionsModel.self, field: "sendMessagesHistory", defaultValue: "1"),
        ]
    }
}
