//
//  InterpolationEngine.swift
//  TranslationKit
//
//  Replaces positional printf-style placeholders with caller-provided arguments.
//  Format matches Android convention: %1$s (1-indexed positional).
//

import Foundation

// MARK: - InterpolationEngine

struct InterpolationEngine {

    /// Replaces %1$s → args[0], %2$s → args[1], etc.
    ///
    /// Rules:
    /// - Indices are 1-based (%1$s maps to args[0]).
    /// - Out-of-range placeholders are left as-is in the output.
    /// - Extra args beyond the number of placeholders are silently ignored.
    /// - If args is empty the template is returned unchanged.
    func interpolate(template: String, args: [String]) -> String {
        guard !args.isEmpty else { return template }
        var result = template
        for (index, arg) in args.enumerated() {
            let placeholder = "%\(index + 1)$s"
            result = result.replacingOccurrences(of: placeholder, with: arg)
        }
        return result
    }
}
