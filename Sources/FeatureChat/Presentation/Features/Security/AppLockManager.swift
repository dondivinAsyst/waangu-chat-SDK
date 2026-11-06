//import Foundation
//import SwiftUI
//import Combine
//import SharedUI
//
//// MARK: - Local Biometric Authentication Protocol (to avoid AuthKit coupling)
//
//enum BiometricType {
//    case faceID
//    case touchID
//    case none
//    case opticID
//    case unknown
//}
//
//protocol BiometricAuthenticatorProtocol {
//    func biometricType() -> BiometricType
//    func isBiometricAvailable() -> Bool
//    func authenticate(reason: String) async throws -> Bool
//}
//
//// MARK: - Simple Implementation (for decoupling from AuthKit)
//
//final class LocalBiometricAuthenticator: BiometricAuthenticatorProtocol {
//    func biometricType() -> BiometricType {
//        // Simple implementation - in real app this would check device capabilities
//        return .touchID // Default fallback
//    }
//    
//    func isBiometricAvailable() -> Bool {
//        // Simple implementation - always return false to disable biometrics for now
//        return false
//    }
//    
//    func authenticate(reason: String) async throws -> Bool {
//        // Simple implementation - always fail for now to maintain security
//        return false
//    }
//}
//
//enum AppLockTimeout: Int, CaseIterable, Codable {
//    case immediately = 0
//    case oneMinute = 60
//    case fifteenMinutes = 900
//    case oneHour = 3600
//
//    var displayName: String {
//        switch self {
//        case .immediately: return "Immediately"
//        case .oneMinute: return "After 1 minute"
//        case .fifteenMinutes: return "After 15 minutes"
//        case .oneHour: return "After 1 hour"
//        }
//    }
//}
//
//final class AppLockManager: ObservableObject {
//
//    static let shared = AppLockManager()
//
//    @AppStorage("appLock.enabled") var isEnabled: Bool = false
//    @AppStorage("appLock.timeout") var lockTimeout: Int = AppLockTimeout.immediately.rawValue
//
//    @Published var isLocked: Bool = false
//    @Published var showLockScreen: Bool = false
//
//     let biometricAuth = BiometricAuthenticator()
//    private var backgroundDate: Date?
//    private var cancellables = Set<AnyCancellable>()
//
//    var timeout: AppLockTimeout {
//        get { AppLockTimeout(rawValue: lockTimeout) ?? .immediately }
//        set { lockTimeout = newValue.rawValue }
//    }
//
//    var biometricTypeName: String {
//        switch biometricAuth.biometricType() {
//        case .faceID: return "Face ID"
//        case .touchID: return "Touch ID"
//        case .none: return "Passcode"
//        case .opticID: return "Optic ID"
//        case .unknown: return "Unknown"
//            
//        }
//    }
//
//    var isBiometricAvailable: Bool {
//        biometricAuth.isBiometricAvailable()
//    }
//
//    private init() {
//        observeAppLifecycle()
//    }
//
//    // MARK: - Lifecycle
//
//    private func observeAppLifecycle() {
//        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
//            .sink { [weak self] _ in
//                self?.backgroundDate = Date()
//                if self?.isEnabled == true {
//                    self?.showLockScreen = true
//                }
//            }
//            .store(in: &cancellables)
//
//        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
//            .sink { [weak self] _ in
//                self?.checkLockOnForeground()
//            }
//            .store(in: &cancellables)
//    }
//
//    private func checkLockOnForeground() {
//        guard isEnabled else {
//            isLocked = false
//            showLockScreen = false
//            return
//        }
//
//        if let bgDate = backgroundDate {
//            let elapsed = Date().timeIntervalSince(bgDate)
//            if elapsed >= TimeInterval(lockTimeout) {
//                isLocked = true
//                showLockScreen = true
//            } else {
//                isLocked = false
//                showLockScreen = false
//            }
//        }
//    }
//
//    // MARK: - Unlock
//
//    func unlock() async -> Bool {
//        do {
//            let success = try await biometricAuth.authenticate(reason: "Unlock Waangu")
//            await MainActor.run {
//                if success {
//                    isLocked = false
//                    showLockScreen = false
//                }
//            }
//            return success
//        } catch {
//            return false
//        }
//    }
//}
//
//// MARK: - Lock Screen View
//
//@available(iOS 17.0, *)
//struct AppLockScreenView: View {
//
//    @ObservedObject var lockManager: AppLockManager
//
//    var body: some View {
//        ZStack {
//            Color(.systemBackground)
//                .ignoresSafeArea()
//
//            VStack(spacing: 32) {
//                Image(systemName: "lock.fill")
//                    .font(.system(size: 48))
//                    .foregroundStyle(.secondary)
//
//                Text("Waangu is Locked")
//                    .font(.title2.weight(.semibold))
//
//                Text("Tap to unlock with \(lockManager.biometricTypeName)")
//                    .font(.subheadline)
//                    .foregroundStyle(.secondary)
//
//                Button {
//                    Task { await lockManager.unlock() }
//                } label: {
//                    Label(
//                        "Unlock",
//                        systemImage: lockManager.biometricAuth.biometricType() == .faceID
//                            ? "faceid"
//                            : "touchid"
//                    )
//                    .font(.headline)
//                    .padding(.horizontal, 32)
//                    .padding(.vertical, 14)
//                    .background(AppColors.primary)
//                    .foregroundStyle(.white)
//                    .clipShape(Capsule())
//                }
//            }
//        }
//        .task {
//            await lockManager.unlock()
//        }
//    }
//}
//
//// MARK: - App Lock Settings View
//
//@available(iOS 17.0, *)
//struct AppLockSettingsView: View {
//
//    @ObservedObject var lockManager = AppLockManager.shared
//
//    var body: some View {
//        List {
//            Section {
//                Toggle("App Lock", isOn: $lockManager.isEnabled)
//            } footer: {
//                Text("Lock Waangu with \(lockManager.biometricTypeName) when you open it.")
//            }
//
//            if lockManager.isEnabled {
//                Section("Auto-Lock") {
//                    ForEach(AppLockTimeout.allCases, id: \.self) { timeout in
//                        Button {
//                            lockManager.timeout = timeout
//                        } label: {
//                            HStack {
//                                Text(timeout.displayName)
//                                Spacer()
//                                if lockManager.timeout == timeout {
//                                    Image(systemName: "checkmark")
//                                        .foregroundStyle(AppColors.primary)
//                                }
//                            }
//                        }
//                        .buttonStyle(.plain)
//                    }
//                }
//            }
//        }
//        .navigationTitle("App Lock")
//        .navigationBarTitleDisplayMode(.inline)
//    }
//}
