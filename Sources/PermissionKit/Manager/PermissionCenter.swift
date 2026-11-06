//
//  PermissionCenter.swift
//  AppModules
//
//  Created by Asyst on 3/24/26.
//

import Foundation
import UIKit
import CoreLocation
import AVFoundation
import UserNotifications
import Contacts
import Photos
import WaanguCoreKit

/// Point d'entrée unique pour toutes les permissions système.
///
/// - `@MainActor` : CLLocationManager exige le main thread pour son delegate.
/// - Singleton via `shared` — une seule instance gère toutes les permissions.
/// - Pattern stream : subscribe → état initial → mises à jour.
///
/// Détection des changements :
///   - Location : delegate `locationManagerDidChangeAuthorization` (temps réel)
///   - Autres : re-check au `didBecomeActive` (retour depuis Settings)
///
/// Usage :
/// ```swift
/// let center = PermissionCenter.shared
///
/// // One-shot
/// let status = await center.status(for: .camera)
///
/// // Request
/// let result = await center.request(.notifications)
///
/// // Stream
/// for await status in center.statusStream(for: .locationWhenInUse) {
///     // Premier yield = état initial, puis mises à jour
/// }
/// ```
@MainActor
public final class PermissionCenter: NSObject, PermissionServiceProtocol, @unchecked Sendable {

    public static let shared = PermissionCenter()

    private let locationManager: CLLocationManager
    private let state = PermissionState()
    private var locationRequestContinuation: CheckedContinuation<PermissionStatus, Never>?
    private var foregroundTask: Task<Void, Never>?

    override private init() {
        self.locationManager = CLLocationManager()
        super.init()
        locationManager.delegate = self
        startForegroundMonitoring()
    }

    deinit {
        foregroundTask?.cancel()
    }

    // MARK: - Status

    public func status(for type: PermissionType) async -> PermissionStatus {
        switch type {
        case .locationWhenInUse:
            return mapLocationStatus(locationManager.authorizationStatus, requested: .locationWhenInUse)
        case .locationAlways:
            return mapLocationStatus(locationManager.authorizationStatus, requested: .locationAlways)
        case .camera:
            return mapAVStatus(AVCaptureDevice.authorizationStatus(for: .video))
        case .microphone:
            return mapAVStatus(AVCaptureDevice.authorizationStatus(for: .audio))
        case .notifications:
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            return mapNotificationStatus(settings.authorizationStatus)
        case .contacts:
            return mapContactsStatus(CNContactStore.authorizationStatus(for: .contacts))
        case .photoLibrary:
            return mapPhotosStatus(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        }
    }

    // MARK: - Request

    public func request(_ type: PermissionType) async -> PermissionStatus {
        let current = await status(for: type)
        guard current == .notDetermined else { return current }

        let result: PermissionStatus

        switch type {
        case .locationWhenInUse:
            result = await requestLocationPermission(.locationWhenInUse)
        case .locationAlways:
            result = await requestLocationPermission(.locationAlways)
        case .camera:
            await AVCaptureDevice.requestAccess(for: .video)
            result = mapAVStatus(AVCaptureDevice.authorizationStatus(for: .video))
        case .microphone:
            await AVCaptureDevice.requestAccess(for: .audio)
            result = mapAVStatus(AVCaptureDevice.authorizationStatus(for: .audio))
        case .notifications:
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            result = mapNotificationStatus(settings.authorizationStatus)
        case .contacts:
            _ = try? await CNContactStore().requestAccess(for: .contacts)
            result = mapContactsStatus(CNContactStore.authorizationStatus(for: .contacts))
        case .photoLibrary:
            let phStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            result = mapPhotosStatus(phStatus)
        }

        await state.publish(status: result, for: type)
        await AppLogger.shared.log("PermissionCenter: \(type.rawValue) → \(result.rawValue)", level: .info)
        return result
    }

    // MARK: - Stream

    public func statusStream(for type: PermissionType) -> AsyncStream<PermissionStatus> {
        AsyncStream { continuation in
            Task { @MainActor [weak self] in
                guard let self else { return }

                let current = await self.status(for: type)
                continuation.yield(current)
                await self.state.forcePublish(status: current, for: type)

                let id = await self.state.addContinuation(continuation, for: type)

                continuation.onTermination = { [weak self] _ in
                    guard let self else { return }
                    Task {
                        await self.state.removeContinuation(id, for: type)
                    }
                }
            }
        }
    }

    // MARK: - Location Request (delegate-based)

    private func requestLocationPermission(_ type: PermissionType) async -> PermissionStatus {
        await withCheckedContinuation { continuation in
            self.locationRequestContinuation = continuation
            if type == .locationAlways {
                locationManager.requestAlwaysAuthorization()
            } else {
                locationManager.requestWhenInUseAuthorization()
            }
        }
    }

    // MARK: - Foreground Monitoring

    private func startForegroundMonitoring() {
        foregroundTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: UIApplication.didBecomeActiveNotification
            )
            for await _ in notifications {
                await self?.recheckNonLocationPermissions()
            }
        }
    }

    /// Re-vérifie les permissions non-location au retour foreground.
    /// Location est couverte par son delegate en temps réel.
    private func recheckNonLocationPermissions() async {
        let nonLocationTypes: [PermissionType] = [
            .camera, .microphone, .notifications, .contacts, .photoLibrary
        ]
        for type in nonLocationTypes {
            let current = await status(for: type)
            await state.publish(status: current, for: type)
        }
    }

    // MARK: - Mapping Helpers

    private func mapLocationStatus(
        _ clStatus: CLAuthorizationStatus,
        requested: PermissionType
    ) -> PermissionStatus {
        switch clStatus {
        case .notDetermined:       return .notDetermined
        case .restricted:          return .restricted
        case .denied:              return .denied
        case .authorizedAlways:    return .authorized
        case .authorizedWhenInUse:
            return requested == .locationAlways ? .limited : .authorized
        @unknown default:          return .notDetermined
        }
    }

    private func mapAVStatus(_ avStatus: AVAuthorizationStatus) -> PermissionStatus {
        switch avStatus {
        case .notDetermined: return .notDetermined
        case .restricted:    return .restricted
        case .denied:        return .denied
        case .authorized:    return .authorized
        @unknown default:    return .notDetermined
        }
    }

    private func mapNotificationStatus(_ unStatus: UNAuthorizationStatus) -> PermissionStatus {
        switch unStatus {
        case .notDetermined: return .notDetermined
        case .denied:        return .denied
        case .authorized:    return .authorized
        case .provisional:   return .provisional
        case .ephemeral:     return .authorized
        @unknown default:    return .notDetermined
        }
    }

    private func mapContactsStatus(_ cnStatus: CNAuthorizationStatus) -> PermissionStatus {
        switch cnStatus {
        case .notDetermined: return .notDetermined
        case .restricted:    return .restricted
        case .denied:        return .denied
        case .authorized:    return .authorized
        case .limited:       return .limited
        @unknown default:    return .notDetermined
        }
    }

    private func mapPhotosStatus(_ phStatus: PHAuthorizationStatus) -> PermissionStatus {
        switch phStatus {
        case .notDetermined: return .notDetermined
        case .restricted:    return .restricted
        case .denied:        return .denied
        case .authorized:    return .authorized
        case .limited:       return .limited
        @unknown default:    return .notDetermined
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension PermissionCenter: CLLocationManagerDelegate {

    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            let clStatus = manager.authorizationStatus
            let whenInUse = self.mapLocationStatus(clStatus, requested: .locationWhenInUse)
            let always = self.mapLocationStatus(clStatus, requested: .locationAlways)

            await self.state.publish(status: whenInUse, for: .locationWhenInUse)
            await self.state.publish(status: always, for: .locationAlways)

            if let continuation = self.locationRequestContinuation {
                continuation.resume(returning: whenInUse)
                self.locationRequestContinuation = nil
            }
        }
    }
}
