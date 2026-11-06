//
//  DeviceInfo.swift
//  AppModules
//
//  Created by Asyst on 3/24/26.
//

// Propriétés statiques hardware/OS lues depuis UIKit, ProcessInfo et Bundle.
// Toutes les valeurs sont thread-safe (computed properties, pas d'état mutable).
// Utilisé par DeviceInfoProviding pour construire les snapshots.

import UIKit
import Foundation

public struct DeviceInfo {

    // MARK: - Hardware

    public static var processorCount: Int {
        ProcessInfo.processInfo.processorCount
    }

    public static var physicalMemoryMB: Int {
        Int(ProcessInfo.processInfo.physicalMemory / 1_048_576)
    }

    public static var modelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) { ptr in
            String(cString: UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self))
        }
    }

    // MARK: - OS

    public static var systemVersion: String {
        UIDevice.current.systemVersion
    }

    public static var platformOS: String {
        switch UIDevice.current.userInterfaceIdiom {
        case .phone: return "iOS"
        case .pad:   return "iPadOS"
        default:     return "iOS"
        }
    }

    // MARK: - Device Identity

    public static var deviceId: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }

    public static var brandName: String { "Apple" }

    public static var manufacturer: String { "Apple Inc." }

    // MARK: - App

    public static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    public static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }
}
