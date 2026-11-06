// MARK: - RASPMonitor.swift
// Module: SecurityKit
// Implements RuntimeProtectionProviding from CoreKit.
// Continuously monitors the runtime environment for active threats:
// hooking, debugging, binary tampering, screen capture,
// keylogger presence, and reverse engineering tools.

import Foundation
import WaanguCoreKit
import UIKit
import Darwin
import MachO

// MARK: - RASPMonitor

/// Monitors the iOS runtime environment for security threats.
///
/// Start monitoring at app launch via `startContinuousMonitoring()`.
/// Subscribe to `threatStream` for real-time threat changes.
///
/// ```swift
/// let rasp = RASPMonitor(
///     analytics: analytics,
///     crashReporter: crashReporter,
///     pollingInterval: 5
/// )
/// await rasp.startContinuousMonitoring()
///
/// for await threats in rasp.threatStream {
///     if !threats.isEmpty { /* react */ }
/// }
/// ```
public actor RASPMonitor: RuntimeProtectionProviding {

    // MARK: - Properties

    private let pollingInterval: TimeInterval
    private let analytics: any AnalyticsProtocol
    private let crashReporter: any CrashReporterProtocol

    private var monitoringTask: Task<Void, Never>?
    private var currentThreats: Set<EnvironmentThreat> = []

    // nonisolated because:
    // - AsyncStream and its Continuation are both Sendable
    // - They are immutable after init (let)
    // - threatStream must be accessible without await (protocol requirement)
    // - continuation must be accessible from deinit (non-isolated context)
    public nonisolated let threatStream: AsyncStream<Set<EnvironmentThreat>>
    private nonisolated let streamContinuation: AsyncStream<Set<EnvironmentThreat>>.Continuation

    // MARK: - Init

    /// - Parameters:
    ///   - analytics: Analytics tracker for RASP events.
    ///   - crashReporter: Crash reporter for threat breadcrumbs and alerts.
    ///   - pollingInterval: Seconds between each full threat scan.
    ///     Default 5s balances responsiveness vs battery impact.
    public init(
        analytics: any AnalyticsProtocol,
        crashReporter: any CrashReporterProtocol,
        pollingInterval: TimeInterval = 5.0
    ) {
        self.analytics = analytics
        self.crashReporter = crashReporter
        self.pollingInterval = pollingInterval

        let (stream, continuation) = AsyncStream<Set<EnvironmentThreat>>.makeStream()
        self.threatStream = stream
        self.streamContinuation = continuation
    }

    deinit {
        monitoringTask?.cancel()
        streamContinuation.finish()
    }

    // MARK: - RuntimeProtectionProviding

    public func detectThreats() async -> Set<EnvironmentThreat> {
        var threats = Set<EnvironmentThreat>()

        if DetectionChecks.isDebuggerAttached() {
            threats.insert(.debuggerAttached)
        }

        if DetectionChecks.isHookingDetected() {
            threats.insert(.hookingDetected)
        }

        if DetectionChecks.isBinaryTampered() {
            threats.insert(.binaryTampered)
        }

        if await DetectionChecks.isScreenCaptured() {
            threats.insert(.screenCaptureActive)
        }

        if DetectionChecks.isReverseEngineeringToolPresent() {
            threats.insert(.reverseEngineeringTool)
        }

        if DetectionChecks.isKeyloggerSuspected() {
            threats.insert(.keyloggerSuspected)
        }

        return threats
    }

    // MARK: - Continuous Monitoring

    /// Starts a background polling loop that evaluates threats
    /// at each `pollingInterval` and emits changes to `threatStream`.
    public func startContinuousMonitoring() {
        guard monitoringTask == nil else { return }

        analytics.log(DeviceTrustAnalyticsEvent.raspMonitoringStarted)

        monitoringTask = Task { [weak self] in
            guard let self else { return }

            await self.observeScreenCapture()

            while !Task.isCancelled {
                let threats = await self.detectThreats()
                let previous = await self.currentThreats

                if threats != previous {
                    await self.handleThreatChange(from: previous, to: threats)
                }

                try? await Task.sleep(for: .seconds(self.pollingInterval))
            }
        }
    }

    /// Stops the continuous monitoring loop.
    public func stopContinuousMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil

        analytics.log(DeviceTrustAnalyticsEvent.raspMonitoringStopped)
    }

    // MARK: - Private — Threat Lifecycle

    /// Called when the threat set changes. Handles observability
    /// and emits the new set to subscribers.
    private func handleThreatChange(
        from previous: Set<EnvironmentThreat>,
        to current: Set<EnvironmentThreat>
    ) {
        let resolved = previous.subtracting(current)

        // New threats appeared
        if !current.subtracting(previous).isEmpty {
            analytics.log(DeviceTrustAnalyticsEvent.raspThreatDetected(threats: current))
            DeviceTrustBreadcrumbs.threatDetected(crashReporter, threats: current)
        }

        // All threats resolved
        if current.isEmpty && !previous.isEmpty {
            analytics.log(DeviceTrustAnalyticsEvent.raspThreatsCleared)

            crashReporter.addBreadcrumb(
                category: "device_trust",
                message: "All RASP threats cleared (resolved: \(resolved.map(\.rawValue).sorted().joined(separator: ", ")))",
                level: .info,
                data: nil
            )
        }

        currentThreats = current
        streamContinuation.yield(current)
    }

    private func observeScreenCapture() {
        NotificationCenter.default.addObserver(
            forName: UIScreen.capturedDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                guard let self else { return }
                let threats = await self.detectThreats()
                let previous = await self.currentThreats

                if threats != previous {
                    await self.handleThreatChange(from: previous, to: threats)
                }
            }
        }
    }
}

// MARK: - Detection Checks

/// Pure static functions for each threat category.
/// Isolated from the actor so they can be unit-tested independently.
enum DetectionChecks {

    // MARK: Debugger Detection

    /// Checks if a debugger (LLDB, GDB) is attached to the process.
    static func isDebuggerAttached() -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]

        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        if result == 0 {
            let isTraced = (info.kp_proc.p_flag & P_TRACED) != 0
            if isTraced { return true }
        }

        return false
    }

    // MARK: Hooking Detection

    /// Detects dynamic library injection and function hooking
    /// (Frida, Cydia Substrate, fishhook, etc.).
    static func isHookingDetected() -> Bool {
        if hasSuspiciousDylibs() { return true }
        if hasFridaIndicators() { return true }
        if isCriticalFunctionHooked() { return true }

        return false
    }

    /// Scans loaded dylibs for known injection frameworks.
    private static func hasSuspiciousDylibs() -> Bool {
        let suspiciousLibs = [
            "FridaGadget",
            "frida-agent",
            "cynject",
            "libcycript",
            "SubstrateLoader",
            "SSLKillSwitch",
            "MobileSubstrate",
            "TweakInject",
            "libblackjack",
            "libReveal",
            "RevealServer"
        ]

        let imageCount = _dyld_image_count()
        for i in 0..<imageCount {
            guard let imageName = _dyld_get_image_name(i) else { continue }
            let name = String(cString: imageName)

            for suspicious in suspiciousLibs {
                if name.localizedCaseInsensitiveContains(suspicious) {
                    return true
                }
            }
        }

        return false
    }

    /// Checks for Frida-specific runtime artifacts.
    private static func hasFridaIndicators() -> Bool {
        let fridaPorts: [UInt16] = [27042, 27043]

        for port in fridaPorts {
            if isLocalPortOpen(port) { return true }
        }

        return false
    }

    /// Probes whether a local TCP port is listening.
    private static func isLocalPortOpen(_ port: UInt16) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        return result == 0
    }

    /// Validates that critical Security framework functions
    /// haven't been swizzled or hooked.
    private static func isCriticalFunctionHooked() -> Bool {
        guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOLOAD) else {
            return true
        }
        defer { dlclose(handle) }

        guard let sym = dlsym(handle, "SecItemCopyMatching") else {
            return true
        }

        var info = Dl_info()
        guard dladdr(sym, &info) != 0 else { return true }

        let imagePath = String(cString: info.dli_fname)
        if !imagePath.contains("Security") {
            return true
        }

        return false
    }

    // MARK: Binary Tampering

    /// Checks if the app binary has been modified (repackaged, re-signed).
    static func isBinaryTampered() -> Bool {
        if isCodeSignatureMissing() { return true }
        if isCodeSignatureStripped() { return true }

        return false
    }

    private static func isCodeSignatureMissing() -> Bool {
        guard let bundlePath = Bundle.main.bundlePath as String? else { return true }
        let codeSignPath = (bundlePath as NSString).appendingPathComponent("_CodeSignature")
        return !FileManager.default.fileExists(atPath: codeSignPath)
    }

    private static func isCodeSignatureStripped() -> Bool {
        guard let header = _dyld_get_image_header(0) else { return true }

        var cursor = UnsafeRawPointer(header)
            .advanced(by: MemoryLayout<mach_header_64>.size)

        for _ in 0..<header.pointee.ncmds {
            let command = cursor.assumingMemoryBound(to: load_command.self)

            if command.pointee.cmd == LC_CODE_SIGNATURE {
                return false
            }

            cursor = cursor.advanced(by: Int(command.pointee.cmdsize))
        }

        return true
    }

    // MARK: Screen Capture

    /// Checks if the screen is currently being recorded or mirrored.
    @MainActor
    static func isScreenCaptured() -> Bool {
        UIScreen.main.isCaptured
    }

    // MARK: Reverse Engineering Tools

    /// Detects the presence of known reverse engineering or introspection tools.
    static func isReverseEngineeringToolPresent() -> Bool {
        let suspiciousEnvVars = [
            "DYLD_INSERT_LIBRARIES",
            "_MSSafeMode",
            "LLDB_DEBUGSERVER_LOG_FILE"
        ]

        for envVar in suspiciousEnvVars {
            if getenv(envVar) != nil { return true }
        }

        let suspiciousPaths = [
            "/usr/lib/TweakInject",
            "/Library/MobileSubstrate",
            "/usr/lib/substrate",
            "/usr/lib/libhooker.dylib"
        ]

        for path in suspiciousPaths {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }

        return false
    }

    // MARK: Keylogger Detection

    /// Heuristic check for known keylogger dylibs.
    /// For sensitive fields (PIN, PAN), the app should force
    /// secureTextEntry = true at the UI layer.
    static func isKeyloggerSuspected() -> Bool {
        let keyloggerLibs = [
            "iKeyMonitor",
            "mSpy",
            "FlexiSPY",
            "KeyLogger",
            "Spyrix"
        ]

        let imageCount = _dyld_image_count()
        for i in 0..<imageCount {
            guard let imageName = _dyld_get_image_name(i) else { continue }
            let name = String(cString: imageName)

            for lib in keyloggerLibs {
                if name.localizedCaseInsensitiveContains(lib) {
                    return true
                }
            }
        }

        return false
    }
}
