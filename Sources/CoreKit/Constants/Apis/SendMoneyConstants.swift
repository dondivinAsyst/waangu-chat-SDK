import Foundation

/// Shared API constants for wallet-to-wallet send money (`requestTransaction` / confirm pipeline).
public enum SendMoneyConstants {
    /// `SERVICEID` for Waangu wallet → wallet transfers.
    public static let walletToWalletServiceId = "606e69a31ef3388dbb431134"

    public static let defaultSenderClient = "customer"
    public static let defaultReceiverClient = "customer"

    /// `MessageType` for fund-out style wallet transfers (aligned with other Send Money mappers).
    public static let defaultMessageType = "FO"
}
