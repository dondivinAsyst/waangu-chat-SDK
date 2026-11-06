//
//  PushkitManager.swift
//  Pods
//
//  Created by Asyst on 11/11/25.
//

import PushKit
import Foundation
import UIKit
import WaanguCoreKit

class PushKitManager: NSObject, PKPushRegistryDelegate {
    private let voipRegistry: PKPushRegistry
    private var voipToken: String?
    
    override init() {
        voipRegistry = PKPushRegistry(queue: .main)
        super.init()
        setupPushKit()
    }
    
    private func setupPushKit() {
        voipRegistry.delegate = self
        voipRegistry.desiredPushTypes = [.voIP]
        debugLog("📱 PushKit initialized for VoIP")
    }
    
    // MARK: - Réception Notifications VoIP
    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        guard type == .voIP else {
            completion()
            return
        }
        processIncomingPush(payload: payload, completion: completion)
    }

    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType) {
        guard type == .voIP else { return }
        processIncomingPush(payload: payload, completion: nil)
    }

    private func processIncomingPush(payload: PKPushPayload, completion: (() -> Void)?) {
        guard let handle = payload.dictionaryPayload["handle"] as? String,
              let callId = payload.dictionaryPayload["callId"] as? String,
              let uuid = UUID(uuidString: callId) else {
            completion?()
            return
        }

        let hasVideo = payload.dictionaryPayload["hasVideo"] as? Bool ?? false
        let callerName = payload.dictionaryPayload["callerName"] as? String ?? handle
        let callerImage = payload.dictionaryPayload["callerImage"] as? String

        VoipManager.shared.reportIncomingCallFromPush(
            uuid: uuid,
            handle: handle,
            hasVideo: hasVideo,
            name: callerName,
            image: callerImage,
            onReported: completion
        )
    }
    
    // MARK: - Gestion du Token VoIP
    func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }
        
        let token = credentials.token.map { String(format: "%02.2hhx", $0) }.joined()
        self.voipToken = token
        
        // Jamais le jeton lui-même dans la console : elle est lisible depuis
        // un Mac relié à l'appareil, y compris en build de production.
        #if DEBUG
        print("🔑 New VoIP Token received (\(token.count) chars)")
        #endif
        
        // Envoyer au serveur
        sendTokenToServer(token)
        
        // Sauvegarder localement
        UserDefaults.standard.set(token, forKey: "voipToken")
        UserDefaults.standard.set(Date(), forKey: "voipTokenLastUpdate")
    }
    
    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP else { return }
        
        debugLog("❌ VoIP token invalidated")
        self.voipToken = nil
        UserDefaults.standard.removeObject(forKey: "voipToken")
        
        // Notifier le serveur de l'invalidation
        notifyTokenInvalidation()
    }
    
    // MARK: - Communication Serveur
    private func sendTokenToServer(_ token: String) {
        guard let url = URL(string: "https://your-server.com/api/voip/register") else {
            debugLog("❌ Invalid server URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let systemVersion = UIDevice.current.systemVersion
        
        let body: [String: Any] = [
            "voipToken": token,
            "deviceId": deviceId,
            "platform": "ios",
            "appVersion": appVersion,
            "systemVersion": systemVersion,
            "timestamp": Date().timeIntervalSince1970,
            "userId": getCurrentUserId() // À implémenter selon votre auth
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    debugLog("❌ Failed to send VoIP token: \(error)")
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    debugLog("❌ Invalid server response")
                    return
                }
                
                if httpResponse.statusCode == 200 {
                    debugLog("✅ VoIP token successfully registered with server")
                    UserDefaults.standard.set(true, forKey: "voipTokenRegistered")
                } else {
                    debugLog("❌ Server returned error: \(httpResponse.statusCode)")
                }
            }.resume()
            
        } catch {
            debugLog("❌ Failed to serialize token data: \(error)")
        }
    }
    
    private func notifyTokenInvalidation() {
        guard let deviceId = UIDevice.current.identifierForVendor?.uuidString else { return }
        
        let url = URL(string: "https://your-server.com/api/voip/unregister")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "deviceId": deviceId,
            "platform": "ios",
            "timestamp": Date().timeIntervalSince1970
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request).resume()
    }
    
    // MARK: - Utilitaires
    func getCurrentVoipToken() -> String? {
        return voipToken ?? UserDefaults.standard.string(forKey: "voipToken")
    }
    
    func isVoipTokenRegistered() -> Bool {
        return UserDefaults.standard.bool(forKey: "voipTokenRegistered")
    }
    
    func refreshVoipToken() {
        // Forcer la régénération du token si nécessaire
        voipRegistry.desiredPushTypes = []
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.voipRegistry.desiredPushTypes = [.voIP]
            debugLog("🔄 VoIP token refresh requested")
        }
    }
    
    private func getCurrentUserId() -> String {
        // Implémentez votre logique d'authentification
        // Exemple :
        return UserDefaults.standard.string(forKey: "currentUserId") ?? "unknown"
    }
    
    // MARK: - Gestion des Erreurs
    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType, with error: Error) {
        debugLog("❌ VoIP token invalidation error: \(error)")
    }
    
    // MARK: - Debug et Logs
    func printDebugInfo() {
        debugLog("""
        📱 PushKit Debug Info:
        - VoIP Token: \(voipToken?.prefix(8) ?? "none")...
        - Token Registered: \(isVoipTokenRegistered())
        - Device ID: \(UIDevice.current.identifierForVendor?.uuidString ?? "unknown")
        - Last Update: \(UserDefaults.standard.object(forKey: "voipTokenLastUpdate") as? Date ?? Date.distantPast)
        """)
    }
    
    // MARK: - Nettoyage
    deinit {
        debugLog("🧹 PushKitManager deinitialized")
    }
}

// MARK: - Utilisation dans VoipManager
extension VoipManager {
    func setupPushKit() {
        // Cette méthode est déjà appelée dans l'init de VoipManager
        // PushKitManager s'initialise automatiquement
    }
    
//    func getPushKitDebugInfo() -> String {
//        return """
//        PushKit Status:
//        - Token: \(pushKit?.getCurrentVoipToken()?.prefix(8) ?? "none")...
//        - Registered: \(pushKit?.isVoipTokenRegistered() == true ? "Yes" : "No")
//        """
//    }
}




