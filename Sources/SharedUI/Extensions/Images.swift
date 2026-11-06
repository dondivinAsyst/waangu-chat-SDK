//
//  Images.swift
//  AppModules
//
//  Created by Asyst on 3/27/26.
//

import UIKit

public extension UIImage {
    /// Attempts to load an image by name using multiple fallback strategies.
    /// Covers asset catalogs, bundle subpaths, and loose PNG files added as
    /// folder references rather than asset catalog entries.
    static func bundleLookup(named name: String) -> UIImage? {
        if let img = UIImage(named: name) { return img }

        let pathPrefixes = ["Modules/Shared/Images/", "Waangu/Modules/Shared/Images/"]
        for prefix in pathPrefixes {
            if let img = UIImage(named: prefix + name) { return img }
        }

        let candidates = [name, name.lowercased()]
        let subdirectories = ["Features/Wallet/Images", "Modules/Shared/Images", "Waangu/Modules/Shared/Images", ""]
        let extensions = ["png", "jpg", "jpeg"]

        for candidate in candidates {
            for dir in subdirectories {
                let directory: String? = dir.isEmpty ? nil : dir
                for ext in extensions {
                    if let path = Bundle.main.path(forResource: candidate, ofType: ext, inDirectory: directory),
                       FileManager.default.fileExists(atPath: path),
                       let img = UIImage(contentsOfFile: path) {
                        return img
                    }
                    if let url = Bundle.main.url(forResource: candidate, withExtension: ext, subdirectory: directory),
                       let img = UIImage(contentsOfFile: url.path) {
                        return img
                    }
                }
            }
        }

        for ext in extensions {
            if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) {
                let lower = name.lowercased()
                if let match = urls.first(where: { $0.lastPathComponent.lowercased().contains(lower) }) {
                    if let img = UIImage(contentsOfFile: match.path) { return img }
                }
            }
        }

        for ext in extensions {
            if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: "Modules/Shared/Images") {
                let lower = name.lowercased()
                if let match = urls.first(where: { $0.lastPathComponent.lowercased().hasPrefix(lower) || $0.lastPathComponent.lowercased().contains(lower) }) {
                    if let img = UIImage(contentsOfFile: match.path) { return img }
                }
            }
        }

        return nil
    }
}
