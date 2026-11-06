import Foundation

/// Where the shares this device is publishing survive a relaunch.
///
/// A protocol rather than a concrete store because the thing that reads it —
/// the session manager — is presentation, and the thing that writes it is a
/// local data source. Only `ChatFeature` knows both.
protocol LiveLocationSessionStoring {
    /// Stored shares that have not yet expired.
    func load(asOf now: Date) -> [LiveLocationShareSession]
    func upsert(_ session: LiveLocationShareSession)
    func remove(shareId: String)
    func removeAll()
}

extension LiveLocationSessionStoring {
    func load() -> [LiveLocationShareSession] { load(asOf: Date()) }
}
