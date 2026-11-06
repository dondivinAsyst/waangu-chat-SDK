//
//  String+Extensions.swift
//  AppModules
//
//  Created by Asyst on 3/23/26.
//

import Foundation
 
public extension String {
 
    /// Retourne uniquement les chiffres de la string.
    /// Utilisé pour normaliser les numéros de version.
    /// Ex : `"1.2.3"` → `"123"`
    func formattedAppVersion() -> String {
        trimmingCharacters(in: .whitespaces)
            .filter { $0.isNumber }
    }
 
    /// `true` si la string est vide après suppression des espaces.
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
 
    /// Retourne `nil` si la string est vide ou ne contient que des espaces.
    var nilIfBlank: String? {
        isBlank ? nil : self
    }
 
    /// Tronque la string à `maxLength` caractères avec suffixe optionnel.
    /// Ex : `"Hello World".truncated(to: 5)` → `"Hello…"`
    func truncated(to maxLength: Int, suffix: String = "…") -> String {
        guard count > maxLength else { return self }
        return String(prefix(maxLength)) + suffix
    }
    var cleanedBase64: String {
        self
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    var isEmptyOrWhitespace: Bool {
        self.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
