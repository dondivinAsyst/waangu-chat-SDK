import Foundation
import UIKit

/// Builds reply snapshots for status segments (same `replyTo*` fields as chat replies).
enum StatusReplySnapshotBuilder {

  /// Short label stored in `replyToMessagePreview` — matches media reply labels (`Photo`, `Video`, …).
  static let previewLabel = "Status"

  static func buildReply(from item: StatusItem, ownerName: String?) -> MessageReply {
    var content = MessageContent()

    switch item.type {
    case .text:
      if let text = item.content?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
        content.text = text
      }
    case .image, .video:
      if let thumbURL = resolveThumbnailURL(for: item) {
        content.thumbnail = thumbURL
        content.image = thumbURL
      }
    case .audio:
      if let thumbURL = normalizeThumbnailSource(item.thumbnail) {
        content.thumbnail = thumbURL
      }
    }

    let snapshot = MessageDataItem(
      codeMessage: item.codeStatus,
      senderId: item.userId,
      senderAvatar: item.userImage,
      senderName: ownerName ?? item.userName ?? "",
      typeMessage: .STATUS,
      message: content,
      createdAt: item.createdAt
    )
    return .message(snapshot)
  }

  static func resolveThumbnailURL(for item: StatusItem) -> String? {
    switch item.type {
    case .text:
      return nil
    case .image:
      if let normalized = normalizeThumbnailSource(item.thumbnail) { return normalized }
      if let disk = StatusLocalMediaResolver.diskImage(for: item) {
        return imageToDataURL(disk)
      }
      return normalizeThumbnailSource(item.content)
    case .video:
      if let normalized = normalizeThumbnailSource(item.thumbnail) { return normalized }
      if let poster = StatusLocalMediaResolver.diskImage(for: item) {
        return imageToDataURL(poster)
      }
      return normalizeThumbnailSource(item.content)
    case .audio:
      return normalizeThumbnailSource(item.thumbnail)
    }
  }

  // MARK: - Private

  private static func normalizeThumbnailSource(_ raw: String?) -> String? {
    guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
      return nil
    }
    if raw.hasPrefix("data:image") { return raw }
    if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return raw }
    if let image = loadUIImage(from: raw) {
      return imageToDataURL(image)
    }
    return raw
  }

  private static func loadUIImage(from path: String) -> UIImage? {
    let url: URL?
    if path.hasPrefix("file://") {
      url = URL(string: path)
    } else if path.hasPrefix("/") {
      url = URL(fileURLWithPath: path)
    } else {
      url = URL(string: path)
    }
    guard let fileURL = url,
          let data = try? Data(contentsOf: fileURL),
          let image = UIImage(data: data) else {
      return nil
    }
    return image
  }

  private static func renderTextStatusThumbnail(for item: StatusItem) -> String? {
    let canvasSize = CGSize(width: 120, height: 120)
    let text = item.content ?? ""
    let background = UIColor(hex: item.background ?? "#000000") ?? .black
    let scaledFontSize = max(10, CGFloat(item.fontSize ?? 32) * 0.28)
    let font = uiFont(
      family: item.fontText,
      size: scaledFontSize,
      weight: item.fontWeight
    )

    let renderer = UIGraphicsImageRenderer(size: canvasSize)
    let image = renderer.image { context in
      background.setFill()
      context.fill(CGRect(origin: .zero, size: canvasSize))

      guard !text.isEmpty else { return }

      let paragraph = NSMutableParagraphStyle()
      paragraph.alignment = .center
      paragraph.lineBreakMode = .byTruncatingTail

      let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: UIColor.white,
        .paragraphStyle: paragraph,
      ]
      let inset = CGRect(
        x: 6,
        y: 6,
        width: canvasSize.width - 12,
        height: canvasSize.height - 12
      )
      (text as NSString).draw(
        with: inset,
        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
        attributes: attributes,
        context: nil
      )
    }
    return imageToDataURL(image, quality: 0.75, maxDimension: 120)
  }

  private static func uiFont(family: String?, size: CGFloat, weight: String?) -> UIFont {
    if let family, !family.isEmpty, family.lowercased() != "system",
       let custom = UIFont(name: family, size: size) {
      return custom
    }
    return UIFont.systemFont(ofSize: size, weight: uiFontWeight(weight))
  }

  private static func uiFontWeight(_ raw: String?) -> UIFont.Weight {
    switch raw?.lowercased() {
    case "100", "ultralight": return .ultraLight
    case "200", "thin":       return .thin
    case "300", "light":      return .light
    case "400", "regular":    return .regular
    case "500", "medium":     return .medium
    case "600", "semibold":   return .semibold
    case "700", "bold":       return .bold
    case "800", "heavy":      return .heavy
    case "900", "black":      return .black
    default:                  return .regular
    }
  }
}

private extension UIColor {
  convenience init?(hex: String) {
    var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if sanitized.hasPrefix("#") {
      sanitized.removeFirst()
    }
    guard sanitized.count == 6 || sanitized.count == 8 else { return nil }

    var value: UInt64 = 0
    guard Scanner(string: sanitized).scanHexInt64(&value) else { return nil }

    let r, g, b, a: CGFloat
    if sanitized.count == 8 {
      r = CGFloat((value & 0xFF00_0000) >> 24) / 255
      g = CGFloat((value & 0x00FF_0000) >> 16) / 255
      b = CGFloat((value & 0x0000_FF00) >> 8) / 255
      a = CGFloat(value & 0x0000_00FF) / 255
    } else {
      r = CGFloat((value & 0xFF0000) >> 16) / 255
      g = CGFloat((value & 0x00FF00) >> 8) / 255
      b = CGFloat(value & 0x0000FF) / 255
      a = 1
    }
    self.init(red: r, green: g, blue: b, alpha: a)
  }
}
