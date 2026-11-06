//
//  Int+Extension.swift
//  AppModules
//
//  Created by Don divin on 5/6/26.
//


import Foundation
//
//extension Int {
//
//    /// Converts bytes to human-readable string (KB, MB, GB, etc.)
//    func formattedFileSize() -> String {
//        let bytes = Double(self)
//        let kb = bytes / 1024
//        let mb = kb / 1024
//        let gb = mb / 1024
//
//        let formatter = NumberFormatter()
//        formatter.maximumFractionDigits = 2
//        formatter.minimumFractionDigits = 0
//
//        switch bytes {
//        case 0..<1024:
//            return "\(self) B"
//        case 1024..<1024*1024:
//            return "\(formatter.string(from: NSNumber(value: kb)) ?? "0") KB"
//        case 1024*1024..<1024*1024*1024:
//            return "\(formatter.string(from: NSNumber(value: mb)) ?? "0") MB"
//        default:
//            return "\(formatter.string(from: NSNumber(value: gb)) ?? "0") GB"
//        }
//    }
//}
extension Int {
    public static let fileSizeFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    /// Converts a size in bytes to human-readable string (B, KB, MB, GB).
    public func formattedFileSize() -> String {
        let bytes = Double(self)
        let kb = bytes / 1024
        let mb = kb / 1024
        let gb = mb / 1024
        let formatter = Self.fileSizeFormatter

        switch bytes {
        case 0..<1024:
            return "\(self) B"
        case 1024..<1024 * 1024:
            return "\(formatter.string(from: NSNumber(value: kb)) ?? "0") KB"
        case 1024 * 1024..<1024 * 1024 * 1024:
            return "\(formatter.string(from: NSNumber(value: mb)) ?? "0") MB"
        default:
            return "\(formatter.string(from: NSNumber(value: gb)) ?? "0") GB"
        }
    }
}
