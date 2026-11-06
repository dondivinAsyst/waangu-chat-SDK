import Foundation
import UIKit

/// Device integrity and security signals
/// Used to detect compromised devices and security risks
public actor DeviceIntegritySignals {
    
    public static let shared = DeviceIntegritySignals()
    
    private var cachedSignals: IntegrityReport?
    private var lastCheckTime: Date?
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes
    
    private init() {}
    
    // MARK: - Public API
    
    /// Get current device integrity report
    public func getIntegrityReport() async -> IntegrityReport {
        // Return cached report if still valid
        if let cached = cachedSignals,
           let lastCheck = lastCheckTime,
           Date().timeIntervalSince(lastCheck) < cacheValidityDuration {
            return cached
        }
        
        // Generate new report
        let report = await generateReport()
        cachedSignals = report
        lastCheckTime = Date()
        return report
    }
    
    /// Force refresh integrity signals
    public func refresh() async -> IntegrityReport {
        let report = await generateReport()
        cachedSignals = report
        lastCheckTime = Date()
        return report
    }
    
    /// Check if device is trusted
    public func isDeviceTrusted() async -> Bool {
        let report = await getIntegrityReport()
        return report.overallTrustLevel == .trusted
    }
    
    // MARK: - Private Helpers
    
    private func generateReport() async -> IntegrityReport {
        let isJailbroken = await checkJailbreak()
        let isDebuggerAttached = checkDebugger()
        let isSimulator = checkSimulator()
        let hasProxyDetected = await checkProxy()
        let isDevModeEnabled = checkDeveloperMode()
        
        let trustLevel = calculateTrustLevel(
            jailbroken: isJailbroken,
            debugger: isDebuggerAttached,
            simulator: isSimulator,
            proxy: hasProxyDetected,
            devMode: isDevModeEnabled
        )
        
        return IntegrityReport(
            isJailbroken: isJailbroken,
            isDebuggerAttached: isDebuggerAttached,
            isSimulator: isSimulator,
            hasProxyDetected: hasProxyDetected,
            isDevModeEnabled: isDevModeEnabled,
            deviceModel: UIDevice.current.model,
            systemVersion: UIDevice.current.systemVersion,
            overallTrustLevel: trustLevel,
            timestamp: Date()
        )
    }
    
    private func checkJailbreak() async -> Bool {
        // Check for common jailbreak indicators
        let jailbreakPaths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt/",
            "/private/var/lib/cydia",
            "/private/var/mobile/Library/SBSettings/Themes",
            "/private/var/tmp/cydia.log",
            "/private/var/stash",
            "/usr/libexec/sftp-server",
            "/usr/bin/ssh"
        ]
        
        // Check if any jailbreak files exist
        for path in jailbreakPaths {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }
        
        // Check if we can write outside sandbox
        let testPath = "/private/jailbreak_test.txt"
        do {
            try "test".write(toFile: testPath, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(atPath: testPath)
            return true
        } catch {
            // Cannot write outside sandbox - good sign
        }
        
        // Check for suspicious URL schemes
        if let url = URL(string: "cydia://package/com.example.package") {
            if UIApplication.shared.canOpenURL(url) {
                return true
            }
        }
        
        return false
    }
    
    private func checkDebugger() -> Bool {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        
        if result != 0 {
            return false
        }
        
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }
    
    private func checkSimulator() -> Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    
    private func checkProxy() async -> Bool {
        // Check system proxy settings
        if let proxySettings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] {
            if let httpProxy = proxySettings["HTTPProxy"] as? String, !httpProxy.isEmpty {
                return true
            }
            if let httpsProxy = proxySettings["HTTPSProxy"] as? String, !httpsProxy.isEmpty {
                return true
            }
        }
        return false
    }
    
    private func checkDeveloperMode() -> Bool {
        // Check if developer mode is enabled (iOS 16+)
        if #available(iOS 16.0, *) {
            // Developer mode indicators
            let devModeIndicators = [
                "/var/mobile/Library/Preferences/com.apple.developer.mode.plist"
            ]
            
            for path in devModeIndicators {
                if FileManager.default.fileExists(atPath: path) {
                    return true
                }
            }
        }
        return false
    }
    
    private func calculateTrustLevel(
        jailbroken: Bool,
        debugger: Bool,
        simulator: Bool,
        proxy: Bool,
        devMode: Bool
    ) -> TrustLevel {
        // Critical issues
        if jailbroken {
            return .compromised
        }
        
        // High risk issues
        if debugger {
            return .suspicious
        }
        
        // Medium risk issues
        var riskCount = 0
        if simulator { riskCount += 1 }
        if proxy { riskCount += 1 }
        if devMode { riskCount += 1 }
        
        if riskCount >= 2 {
            return .suspicious
        } else if riskCount == 1 {
            return .caution
        }
        
        return .trusted
    }
}

// MARK: - Models

public struct IntegrityReport: Sendable, Codable {
    public let isJailbroken: Bool
    public let isDebuggerAttached: Bool
    public let isSimulator: Bool
    public let hasProxyDetected: Bool
    public let isDevModeEnabled: Bool
    public let deviceModel: String
    public let systemVersion: String
    public let overallTrustLevel: TrustLevel
    public let timestamp: Date
    
    /// Whether device should be blocked from sensitive operations
    public var shouldBlockSensitiveOperations: Bool {
        overallTrustLevel == .compromised || isJailbroken
    }
    
    /// Whether to show security warning to user
    public var shouldShowWarning: Bool {
        overallTrustLevel == .suspicious || overallTrustLevel == .compromised
    }
}

public enum TrustLevel: String, Sendable, Codable {
    case trusted = "TRUSTED"
    case caution = "CAUTION"
    case suspicious = "SUSPICIOUS"
    case compromised = "COMPROMISED"
    
    public var description: String {
        switch self {
        case .trusted:
            return "Device is trusted"
        case .caution:
            return "Device requires caution"
        case .suspicious:
            return "Device shows suspicious activity"
        case .compromised:
            return "Device is compromised"
        }
    }
}

// MARK: - Protocol

public protocol DeviceIntegrityChecking {
    func checkIntegrity() async -> IntegrityReport
    func isDeviceTrusted() async -> Bool
}

extension DeviceIntegritySignals: DeviceIntegrityChecking {
    public func checkIntegrity() async -> IntegrityReport {
        await getIntegrityReport()
    }
}
