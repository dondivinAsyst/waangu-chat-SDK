import Foundation
import CryptoKit

public final class X3DHService {

    /// Called by the INITIATOR when opening a new conversation.
    /// Fetches the recipient's PublicKeyBundle, performs 3 (or 4) DH
    /// computations, and returns a fresh SessionState plus the ephemeral
    /// public key that must be sent alongside the first message.
    public static func initiateSession(
        myIdentityKey: Curve25519.KeyAgreement.PrivateKey,
        theirBundle: PublicKeyBundle
    ) throws -> (session: SessionState, ephemeralPublicKey: Data) {

        let theirIdentity = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: theirBundle.identityKey
        )
        let theirSignedPreKey = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: theirBundle.signedPreKey
        )

        let ephemeralKey = Curve25519.KeyAgreement.PrivateKey()

        // DH1: my identity × their signed pre-key
        let dh1 = try myIdentityKey.sharedSecretFromKeyAgreement(with: theirSignedPreKey)
        // DH2: my ephemeral × their identity
        let dh2 = try ephemeralKey.sharedSecretFromKeyAgreement(with: theirIdentity)
        // DH3: my ephemeral × their signed pre-key
        let dh3 = try ephemeralKey.sharedSecretFromKeyAgreement(with: theirSignedPreKey)

        var masterSecret = Data()
        dh1.withUnsafeBytes { masterSecret.append(contentsOf: $0) }
        dh2.withUnsafeBytes { masterSecret.append(contentsOf: $0) }
        dh3.withUnsafeBytes { masterSecret.append(contentsOf: $0) }

        // DH4 with one-time pre-key (if available)
        if let otpkData = theirBundle.oneTimePreKeys.first {
            let otpk = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: otpkData)
            let dh4 = try ephemeralKey.sharedSecretFromKeyAgreement(with: otpk)
            dh4.withUnsafeBytes { masterSecret.append(contentsOf: $0) }
        }

        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: masterSecret),
            info: Data("WaanguE2EE".utf8),
            outputByteCount: 64
        )
        let derivedData = derived.withUnsafeBytes { Data($0) }

        let sendingRatchetKey = Curve25519.KeyAgreement.PrivateKey()

        let session = SessionState(
            rootKey: Data(derivedData[0..<32]),
            sendingChainKey: Data(derivedData[32..<64]),
            receivingChainKey: nil,
            sendingRatchetPrivateKey: sendingRatchetKey.rawRepresentation,
            sendingRatchetPublicKey: sendingRatchetKey.publicKey.rawRepresentation,
            receivingRatchetPublicKey: theirSignedPreKey.rawRepresentation
        )

        return (session, ephemeralKey.publicKey.rawRepresentation)
    }

    /// Called by the RECIPIENT when they receive the very first message
    /// from a new sender. Mirrors the initiator's DH computations.
    public static func acceptSession(
        myIdentityKey: Curve25519.KeyAgreement.PrivateKey,
        mySignedPreKey: Curve25519.KeyAgreement.PrivateKey,
        myOneTimePreKey: Curve25519.KeyAgreement.PrivateKey?,
        theirIdentityKey: Data,
        theirEphemeralKey: Data
    ) throws -> SessionState {

        let theirIdentity = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: theirIdentityKey
        )
        let theirEphemeral = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: theirEphemeralKey
        )

        // Mirror DH1-3
        let dh1 = try mySignedPreKey.sharedSecretFromKeyAgreement(with: theirIdentity)
        let dh2 = try myIdentityKey.sharedSecretFromKeyAgreement(with: theirEphemeral)
        let dh3 = try mySignedPreKey.sharedSecretFromKeyAgreement(with: theirEphemeral)

        var masterSecret = Data()
        dh1.withUnsafeBytes { masterSecret.append(contentsOf: $0) }
        dh2.withUnsafeBytes { masterSecret.append(contentsOf: $0) }
        dh3.withUnsafeBytes { masterSecret.append(contentsOf: $0) }

        if let otpk = myOneTimePreKey {
            let dh4 = try otpk.sharedSecretFromKeyAgreement(with: theirEphemeral)
            dh4.withUnsafeBytes { masterSecret.append(contentsOf: $0) }
        }

        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: masterSecret),
            info: Data("WaanguE2EE".utf8),
            outputByteCount: 64
        )
        let derivedData = derived.withUnsafeBytes { Data($0) }

        let sendingRatchetKey = Curve25519.KeyAgreement.PrivateKey()

        return SessionState(
            rootKey: Data(derivedData[0..<32]),
            sendingChainKey: Data(derivedData[32..<64]),
            receivingChainKey: nil,
            sendingRatchetPrivateKey: sendingRatchetKey.rawRepresentation,
            sendingRatchetPublicKey: sendingRatchetKey.publicKey.rawRepresentation,
            receivingRatchetPublicKey: theirEphemeral.rawRepresentation
        )
    }
}
