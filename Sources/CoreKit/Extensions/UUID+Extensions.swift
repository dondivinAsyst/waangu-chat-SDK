//
//  UUID+Extensions.swift
//  CoreKit
//

import Foundation

public extension UUID {

    /// The canonical form used across this app: lowercase, dashed.
    ///
    /// Foundation's `uuidString` is uppercase. Mixing the two is a silent bug —
    /// the same UUID written uppercase in one place and lowercase in another
    /// yields strings that never compare equal, so records fail to correlate
    /// rather than failing loudly.
    ///
    /// Use this for every id that leaves the process: payloads, database rows,
    /// logs. Reading stays tolerant — `UUID(uuidString:)` accepts either case.
    var lowercasedString: String {
        uuidString.lowercased()
    }
}
