//
//  Bundle+Extensions.swift
//  AppModules
//
//  Created by Asyst on 3/23/26.
//

import Foundation

public extension Bundle {

    /// Version lisible de l'app — `CFBundleShortVersionString`.
    /// Ex : `"1.2.3"`
    var versionNumber: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// Numéro de build — `CFBundleVersion`.
    /// Ex : `"42"`
    var buildNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    /// Version complète formatée : `"1.2.3 (42)"`
    var fullVersion: String {
        "\(versionNumber) (\(buildNumber))"
    }
}
