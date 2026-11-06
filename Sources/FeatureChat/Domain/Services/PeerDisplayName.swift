//
//  PeerDisplayName.swift
//  FeatureChat
//
//  Keeps identifiers out of the places a person's name belongs.
//

import Foundation

/// Decides whether a stored "name" is actually a name.
///
/// `PeerInfoDTO.displayName` is non-optional, so the server has to put
/// *something* there and sends the peer's account id when it cannot resolve a
/// name. Stored verbatim and rendered verbatim, that is how a chat list ends up
/// with `6a1fe7bc18f5cd1e344b5ab4` where a person should be.
///
/// The test is deliberately narrow. A name is rejected only when it is one of
/// this row's own identifiers, or when it is a bare token shaped like an id and
/// could not plausibly be something a human typed. Anything containing a space,
/// or any word that isn't hex, is left alone — a real name that happens to look
/// odd is far more common than an id that happens to look like a name.
enum PeerDisplayName {

    /// The candidate if it is a usable name, otherwise an empty string.
    ///
    /// - Parameter identifiers: ids known for this row — user id, contact id,
    ///   conversation id. Compared case-insensitively: the same id reaches us
    ///   upper- and lower-cased from different sources.
    static func sanitized(_ candidate: String?, identifiers: [String] = []) -> String {
        let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "" }

        let isKnownIdentifier = identifiers.contains {
            !$0.isEmpty && $0.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        guard !isKnownIdentifier, !looksLikeIdentifier(trimmed) else { return "" }

        return trimmed
    }

    /// The sanitized candidate, or nil when nothing usable is left — for the
    /// optional-string fields a name is stored in.
    static func sanitizedOrNil(_ candidate: String?, identifiers: [String] = []) -> String? {
        let resolved = sanitized(candidate, identifiers: identifiers)
        return resolved.isEmpty ? nil : resolved
    }

    /// True for tokens that are ids by shape: a UUID, or a bare run of hex long
    /// enough to be a generated key (a Mongo ObjectId is 24).
    static func looksLikeIdentifier(_ value: String) -> Bool {
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !token.contains(" ") else { return false }

        if UUID(uuidString: token) != nil { return true }

        // Hyphens included: ids arrive both dashed and undashed, and a name is
        // not 16+ unbroken hex characters either way.
        let hexDigits = token.filter { $0.isHexDigit }
        let separators = token.filter { $0 == "-" || $0 == "_" }
        guard hexDigits.count + separators.count == token.count else { return false }

        return hexDigits.count >= 16
    }
}
