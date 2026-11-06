//
//  Data+Extensions.swift
//  AppModules
//
//  Created by Asyst on 3/23/26.
//
import Foundation

public extension Data {

    /// Appende une String UTF-8 au Data.
    /// Utilisé par MultipartBuilder dans NetworkKit.
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }

    /// Retourne une représentation hexadécimale — utile pour le debug de tokens.
    var hexString: String {
        map { String(format: "%02hhx", $0) }.joined()
    }
}
