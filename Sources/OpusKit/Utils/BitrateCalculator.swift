import Foundation

/// Utility for calculating audio bitrates and file sizes
public enum BitrateCalculator {
    
    /// Calculate expected file size for given duration and bitrate
    /// - Parameters:
    ///   - duration: Duration in seconds
    ///   - bitrate: Bitrate in bits per second
    /// - Returns: Expected file size in bytes
    public static func calculateFileSize(duration: TimeInterval, bitrate: Int) -> Int64 {
        let bits = Int64(duration * Double(bitrate))
        return bits / 8
    }
    
    /// Calculate bitrate from file size and duration
    /// - Parameters:
    ///   - fileSize: File size in bytes
    ///   - duration: Duration in seconds
    /// - Returns: Bitrate in bits per second
    public static func calculateBitrate(fileSize: Int64, duration: TimeInterval) -> Int {
        guard duration > 0 else { return 0 }
        let bits = fileSize * 8
        return Int(Double(bits) / duration)
    }
    
    /// Calculate duration from file size and bitrate
    /// - Parameters:
    ///   - fileSize: File size in bytes
    ///   - bitrate: Bitrate in bits per second
    /// - Returns: Duration in seconds
    public static func calculateDuration(fileSize: Int64, bitrate: Int) -> TimeInterval {
        guard bitrate > 0 else { return 0 }
        let bits = fileSize * 8
        return Double(bits) / Double(bitrate)
    }
    
    /// Format bitrate for display
    /// - Parameter bitrate: Bitrate in bits per second
    /// - Returns: Formatted string (e.g., "64 kbps")
    public static func formatBitrate(_ bitrate: Int) -> String {
        if bitrate >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bitrate) / 1_000_000)
        } else if bitrate >= 1_000 {
            return String(format: "%.0f kbps", Double(bitrate) / 1_000)
        } else {
            return "\(bitrate) bps"
        }
    }
    
    /// Format file size for display
    /// - Parameter bytes: Size in bytes
    /// - Returns: Formatted string (e.g., "1.5 MB")
    public static func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
