//
//  StatusModelMapper.swift
//  FeatureChat
//
//  Maps inbound story MQTT / sync payloads to StatusModel.
//

import Foundation

enum StatusModelMapper {

    static func toModel(from dto: InboundStoryCreatedDTO, at: Date = Date()) -> StatusModel? {
        let storyId = dto.resolvedStoryId
        let creatorId = dto.resolvedCreatorId
        guard !storyId.isEmpty, !creatorId.isEmpty else { return nil }

        let mediaType = mapMediaType(dto.resolvedStoryType)
        let parsedFont = parseFont(dto.resolvedFont)
        let postedAt = parseDate(dto.createdAt) ?? at
        let expiresAt = parseDate(dto.expiresAt) ?? postedAt.addingTimeInterval(24 * 60 * 60)

        return StatusModel(
            id: storyId,
            userId: creatorId,
            userName: dto.resolvedCreatorName,
            avatarURL: dto.resolvedCreatorAvatar,
            segmentIndex: dto.segmentIndex ?? 0,
            totalSegments: max(dto.totalSegments ?? 1, 1),
            mediaType: mediaType,
            text: mediaType == .text ? dto.resolvedContent : nil,
            caption: mediaType != .text ? dto.resolvedCaption : nil,
            mediaURL: mediaType != .text ? dto.resolvedContent : nil,
            thumbnailURL: dto.resolvedThumbnail,
            backgroundColor: dto.resolvedBackground,
            fontStyle: parsedFont.text,
            fontWeight: parsedFont.weight ?? nonEmpty(dto.fontWeight),
            postedAt: postedAt,
            expiresAt: expiresAt,
            syncStatus: .synced,
            createdAt: postedAt,
            updatedAt: Date()
        )
    }

    // MARK: - Helpers

    private static func mapMediaType(_ raw: String) -> StatusMediaTypeModel {
        switch raw.uppercased() {
        case "TEXT":  return .text
        case "IMAGE": return .image
        case "VIDEO": return .video
        default:
            return StatusMediaTypeModel(rawValue: raw.lowercased()) ?? .text
        }
    }

    private static func parseFont(_ value: String?) -> (text: String?, weight: String?) {
        guard let value, !value.isEmpty else { return (nil, nil) }
        let parts = value.split(separator: "|", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            return (parts[0], parts[1])
        }
        return (value, nil)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Supports ISO-8601 with up to nanosecond fractional seconds from the story backend.
    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }

        // Truncate fractional seconds to milliseconds when backend sends >3 digits.
        if let normalized = normalizeFractionalSeconds(raw),
           let date = formatter.date(from: normalized) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: raw) { return date }

        // Fallback: strip fractional part entirely.
        if let dot = raw.firstIndex(of: "."),
           let z = raw.lastIndex(of: "Z") ?? raw.lastIndex(of: "+"),
           dot < z {
            let stripped = String(raw[..<dot]) + String(raw[z...])
            return formatter.date(from: stripped)
        }
        return nil
    }

    private static func normalizeFractionalSeconds(_ raw: String) -> String? {
        guard let dot = raw.firstIndex(of: ".") else { return nil }
        let afterDot = raw.index(after: dot)
        let fractionAndSuffix = raw[afterDot...]
        guard let end = fractionAndSuffix.firstIndex(where: { !$0.isNumber }) else { return nil }

        let fraction = raw[afterDot..<end]
        guard fraction.count > 3 else { return nil }

        let prefix = String(raw[..<afterDot])
        let millis = String(fraction.prefix(3))
        let suffix = String(raw[end...])
        return prefix + millis + suffix
    }
}
