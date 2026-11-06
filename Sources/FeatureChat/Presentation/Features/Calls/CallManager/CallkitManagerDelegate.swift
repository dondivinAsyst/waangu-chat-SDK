//
//  CallkitManagerDelegate.swift
//  Pods
//
//  Created by Asyst on 11/10/25.
//

import Foundation
import Combine
import CallKit
import AVFoundation
import UIKit
import WaanguCoreKit

// MARK: - Delegate Protocol Évolué
protocol CallKitManagerDelegate: AnyObject {
    func onIncoming(uuid: UUID, handle: String, hasVideo: Bool)
    func onAnswered(uuid: UUID)
    func onEnded(uuid: UUID)
    func onStarted(uuid: UUID, handle: String)
    func onMuted(uuid: UUID, isMuted: Bool)
    func onHold(uuid: UUID, isOnHold: Bool)
    /// CallKit owns the audio session during a call; the media stack only starts
    /// playing and capturing once it says the session is live.
    func onAudioSessionActivated(_ isActivated: Bool)
}

// MARK: - CallKit Manager Production
class CallKitManager: NSObject {
    weak var delegate: CallKitManagerDelegate?
    
    private let callController = CXCallController()
    private var provider: CXProvider!
    private var activeCalls: [UUID: ActiveCall] = [:]
    
    // Structure pour gérer les appels actifs
    private struct ActiveCall {
        var handle: String
        let hasVideo: Bool
        var isMuted: Bool = false
        var isOnHold: Bool = false
        var connectedAt: Date?
    }
    
    override init() {
        super.init()
        setupProvider()
    }
    
    private func setupProvider() {
        let configuration = CXProviderConfiguration(localizedName: "Waangu")
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportsVideo = true
        configuration.includesCallsInRecents = true //  Production
        configuration.supportedHandleTypes = [.generic, .phoneNumber]
        configuration.ringtoneSound = "ringtone.caf"
        configuration.iconTemplateImageData = UIImage(named: "callkit-icon")?.pngData()
        
        // 🔧 Configuration avancée production
        configuration.supportsVideo = true
        configuration.supportedHandleTypes = [.generic]
        
        provider = CXProvider(configuration: configuration)
        provider.setDelegate(self, queue: DispatchQueue.main)
    }
    
    // MARK: - Gestion Audio
    //
    // This class no longer touches `AVAudioSession`. Category and mode belong to
    // the media engine, which applies them through `RTCAudioSession` under the
    // configuration lock WebRTC also takes; activation belongs to CallKit.
    // Reaching past either — as this file used to, with `setCategory` and
    // `setActive` on the shared session — left WebRTC's view of the session out
    // of step with the real one and produced calls with no audio at all.
    //
    // The only job left here is to relay `didActivate` / `didDeactivate`.

    // MARK: - Appels Entrants (Production)
    func reportIncomingCall(uuid: UUID, handle: String, hasVideo: Bool, completion: @escaping (Bool) -> Void) {
        debugLog(" Production: Incoming call from \(handle)")
        
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: handle)
        update.hasVideo = hasVideo
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsHolding = true
        update.supportsDTMF = false
        
        provider.reportNewIncomingCall(with: uuid, update: update) { error in
            DispatchQueue.main.async {
                if let error = error {
                    debugLog(" Failed to report incoming call: \(error.localizedDescription)")
                    completion(false)
                } else {
                    debugLog(" Incoming call reported successfully")
                    self.activeCalls[uuid] = ActiveCall(handle: handle, hasVideo: hasVideo)
                    self.delegate?.onIncoming(uuid: uuid, handle: handle, hasVideo: hasVideo)
                    // System CallKit UI owns the ringtone; do not start a
                    // competing playback session here.
                    completion(true)
                }
            }
        }
    }
    
    // MARK: - Appels Sortants (Production)
    func startOutgoingCall(uuid: UUID, handle: String, hasVideo: Bool) {
        debugLog(" Production: Outgoing call to \(handle)")
        
        let handle = CXHandle(type: .generic, value: handle)
        let startCallAction = CXStartCallAction(call: uuid, handle: handle)
        startCallAction.isVideo = hasVideo
        
        let transaction = CXTransaction(action: startCallAction)
        
        callController.request(transaction) { error in
            DispatchQueue.main.async {
                if let error = error {
                    debugLog(" Start call failed: \(error.localizedDescription)")
                } else {
                    debugLog(" Outgoing call started")
                    self.activeCalls[uuid] = ActiveCall(handle: handle.value, hasVideo: hasVideo)
                    
                    // Mettre à jour l'appel sortant
                    let update = CXCallUpdate()
                    update.remoteHandle = handle
                    update.hasVideo = hasVideo
                    
                    self.provider.reportCall(with: uuid, updated: update)
                    self.delegate?.onStarted(uuid: uuid, handle: handle.value)
                }
            }
        }
    }
    
    // MARK: - Contrôles d'Appel Avancés
    func muteCall(uuid: UUID, mute: Bool) {
        guard activeCalls[uuid] != nil else { return }
        
        let muteAction = CXSetMutedCallAction(call: uuid, muted: mute)
        let transaction = CXTransaction(action: muteAction)
        
        callController.request(transaction) { error in
            if let error = error {
                debugLog(" Mute action failed: \(error)")
            } else {
                debugLog(" Call \(mute ? "muted" : "unmuted")")
                self.activeCalls[uuid]?.isMuted = mute
                self.delegate?.onMuted(uuid: uuid, isMuted: mute)
            }
        }
    }
    
    func holdCall(uuid: UUID, hold: Bool) {
        guard activeCalls[uuid] != nil else { return }
        
        let holdAction = CXSetHeldCallAction(call: uuid, onHold: hold)
        let transaction = CXTransaction(action: holdAction)
        
        callController.request(transaction) { error in
            if let error = error {
                debugLog(" Hold action failed: \(error)")
            } else {
                debugLog(" Call \(hold ? "held" : "unheld")")
                self.activeCalls[uuid]?.isOnHold = hold
                // Note: Vous devriez ajouter onHold au protocol delegate si besoin
            }
        }
    }
    
    // MARK: - Gestion Appels
    func answerCall(uuid: UUID) {
        debugLog(" Answering call: \(uuid)")
        activeCalls[uuid]?.connectedAt = Date()
        delegate?.onAnswered(uuid: uuid)
    }

    func endCall(uuid: UUID) {

        debugLog(" Ending call: \(uuid)")

        let endCallAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endCallAction)
        
        callController.request(transaction) { error in
            DispatchQueue.main.async {
                if let error = error {
                    debugLog(" End call failed: \(error.localizedDescription)")
                } else {
                    debugLog(" Call ended successfully")
                    self.activeCalls.removeValue(forKey: uuid)
                    self.delegate?.onEnded(uuid: uuid)
                    // CallKit deactivates the session and calls `didDeactivate`,
                    // which is where the media engine is told to stand down.
                }
            }
        }
    }
    
    func endAllCalls() {
        debugLog(" Ending all calls")
        for uuid in activeCalls.keys {
            endCall(uuid: uuid)
        }
    }

    /// Marks the CX outgoing call as connected once the peer has answered.
    func reportOutgoingCallConnected(uuid: UUID) {
        guard activeCalls[uuid] != nil else { return }
        provider.reportOutgoingCall(with: uuid, connectedAt: Date())
        activeCalls[uuid]?.connectedAt = Date()
    }
    
   private func getActiveCall(uuid: UUID) -> ActiveCall? {
        return activeCalls[uuid]
    }
    
}

// MARK: - CXProviderDelegate Production
extension CallKitManager: CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {
        debugLog(" Provider did reset - Cleaning up")
        activeCalls.removeAll()
        delegate?.onAudioSessionActivated(false)
    }
    
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        debugLog(" CXAnswerCallAction performed")
        answerCall(uuid: action.callUUID)
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        debugLog(" CXEndCallAction performed")
        activeCalls.removeValue(forKey: action.callUUID)
        delegate?.onEnded(uuid: action.callUUID)
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        debugLog("📞 CXStartCallAction performed")

        let update = CXCallUpdate()
        update.remoteHandle = action.handle
        update.hasVideo = action.isVideo
        provider.reportCall(with: action.callUUID, updated: update)

        // Connecting only — `connectedAt` waits for the peer answer
        // (`reportOutgoingCallConnected`). Faking connected after 1s made
        // CallKit think the call was up while we were still ringing.
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())
        action.fulfill()

        if let call = activeCalls[action.callUUID] {
            delegate?.onStarted(uuid: action.callUUID, handle: call.handle)
        }
    }
    
    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        debugLog(" Mute action: \(action.isMuted)")
        activeCalls[action.callUUID]?.isMuted = action.isMuted
        delegate?.onMuted(uuid: action.callUUID, isMuted: action.isMuted)
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        debugLog(" Hold action: \(action.isOnHold)")
        activeCalls[action.callUUID]?.isOnHold = action.isOnHold
        // Implémentez onHold dans le delegate si nécessaire
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        debugLog(" Audio session activated")
        // Hand straight off: the engine is the only thing that may reconfigure
        // the session, and it needs this to bring the VoIP audio unit up.
        delegate?.onAudioSessionActivated(true)
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        debugLog(" Audio session deactivated")
        delegate?.onAudioSessionActivated(false)
    }
    
    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        debugLog(" Action timed out: \(action)")
        // Gérer les timeouts selon le type d'action
    }
}

// MARK: - Extensions Utilitaires
extension CallKitManager {
    func isCallActive(uuid: UUID) -> Bool {
        return activeCalls[uuid] != nil
    }
    
    private func getAllActiveCalls() -> [UUID: ActiveCall] {
        return activeCalls
    }
    
    func updateCallHandle(uuid: UUID, newHandle: String) {
        if var call = activeCalls[uuid] {
            call.handle = newHandle
            activeCalls[uuid] = call
        }
    }
    
    // Méthode pour gérer l'activation depuis l'état killed
    func handleAppActivationWithCall(uuid: UUID) {
        if let call = activeCalls[uuid] {
            debugLog("📱 CallKitManager: App activated with active call")
            
            // Notifier VoipManager pour qu'il mette à jour l'UI
            DispatchQueue.main.async {
                VoipManager.shared.handleCallFromKilledState(
                    uuid: uuid,
                    handle: call.handle,
                    isIncoming: true // ou false selon le contexte
                )
            }
        }
    }
}


