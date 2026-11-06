//
//  DeviceInfoProviding.swift
//  AppModules
//
//  Created by Asyst on 3/23/26.
//

// Implémentation concrète de DeviceInfoProvidingProtocol (défini dans CoreKit).
// UIKit requis — c'est pourquoi elle vit dans DeviceKit et non CoreKit.

import WaanguCoreKit
import UIKit
import Foundation

public final class DeviceInfoProviding: DeviceInfoProvidingProtocol {

    public init() {}

    public nonisolated func captureSnapshot() -> DeviceInfoSnapshot {
        DeviceInfoSnapshot(
            processorCount: DeviceInfo.processorCount,
            physicalMemoryMB: DeviceInfo.physicalMemoryMB,
            modelIdentifier: DeviceInfo.modelIdentifier,
            systemVersion: DeviceInfo.systemVersion
        )
    }

    public nonisolated func captureDeviceContext() -> DeviceContext {
        DeviceContext(
            deviceId: DeviceInfo.deviceId,
            deviceModel: DeviceInfo.modelIdentifier,
            brandName: DeviceInfo.brandName,
            manufacturer: DeviceInfo.manufacturer,
            osVersion: DeviceInfo.systemVersion,
            appVersion: DeviceInfo.appVersion,
            buildNumber: DeviceInfo.buildNumber,
            platformOS: DeviceInfo.platformOS,
            firebaseToken: "TEST-FIREBASE-TOKEN"
        )
    }
}
