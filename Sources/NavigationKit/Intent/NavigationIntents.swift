// NavigationKit/Intent/NavigationIntents.swift

import Foundation

/// Factory methods par feature — déclarés dans NavigationKit
/// pour que tous les modules puissent les utiliser sans import croisé.
public enum NavigationIntents {

    public enum Wallet {
        public static func home() -> NavigationIntent {
            .init(feature: "wallet", screen: "home")
        }

        public static func services(billerFormId: String? = nil) -> NavigationIntent {
            var params: [String: String] = [:]
            if let id = billerFormId { params["billerFormId"] = id }
            return .init(feature: "wallet", screen: "services", params: params)
        }

    }

    public enum Ride {
        public static func home() -> NavigationIntent {
            .init(feature: "ride", screen: "home")
        }
        public static func detail(rideId: String) -> NavigationIntent {
            .init(feature: "ride", screen: "detail", params: ["rideId": rideId])
        }
        public static func booking(vehicleId: String) -> NavigationIntent {
            .init(feature: "ride", screen: "booking", params: ["vehicleId": vehicleId])
        }
    }

    public enum Chat {
        public static func inbox() -> NavigationIntent {
            
            .init(feature: "chat", screen: "inbox")
        }
        public static func conversation(id: String) -> NavigationIntent {
            .init(feature: "chat", screen: "conversation", params: ["id": id])
        }
        
        public static func home() -> NavigationIntent {
            #if DEBUG
            print("this was called to go to chat")
            #endif
                return NavigationIntent(feature: "chat", screen: "home")
        }
        
        public static func share() -> NavigationIntent {
            .init(feature: "chat", screen: "share")
        }

        /// Ouvre le Chat sur un objet financier.
        ///
        /// L'identifiant est **opaque** : il ne porte ni montant, ni bénéficiaire,
        /// ni devise, ni statut. Tout cela se lit auprès du backend, qui vérifie au
        /// passage que l'objet appartient bien à la session courante.
        ///
        /// Une décision financière transportée par une URL est une décision
        /// falsifiable : n'importe qui peut fabriquer le lien.
        public static func financialObject(opaqueId: String) -> NavigationIntent {
            .init(feature: "chat", screen: "financialObject", params: ["opaqueId": opaqueId])
        }

        /// Ouvre un lien de paiement reçu — INTEGRATION_CHAT_FINANCE.md Phase 4.
        ///
        /// Le lien ne porte **que** son `token` et son `nonce` : il ne paie rien
        /// (`executable=false`). Le Chat l'inspecte au serveur, montre la
        /// demande désignée, et le paiement suit le parcours normal — devis,
        /// confirmation explicite.
        public static func paymentLink(token: String, nonce: String) -> NavigationIntent {
            .init(feature: "chat", screen: "paymentLink", params: ["token": token, "nonce": nonce])
        }

        /// Même intention, avec le type d'objet que porte un push financier.
        ///
        /// Le type n'est pas une donnée financière — il dit *quoi* relire, pas
        /// dans quel état c'est — et sans lui l'objet ne peut pas être demandé
        /// au bon endpoint.
        public static func financialObject(opaqueId: String, objectType: String) -> NavigationIntent {
            .init(feature: "chat", screen: "financialObject",
                  params: ["opaqueId": opaqueId, "objectType": objectType])
        }
        
        /// Opens a channel invitation from a shareable link.
        ///
        /// The invite code is the only parameter needed - the backend validates
        /// it and returns the channel details for preview before subscription.
        ///
        /// Format: `waangu://chat/channel/invite/{inviteCode}`
        /// Example: `waangu://chat/channel/invite/ABC123XYZ`
        public static func channelInvite(inviteCode: String) -> NavigationIntent {
            .init(feature: "chat", screen: "channelInvite", params: ["inviteCode": inviteCode])
        }
    }

    public enum Insurance {
        public static func home() -> NavigationIntent {
            #if DEBUG
            print("this was called to go to Insurance")
            #endif
            return NavigationIntent(feature: "insurance", screen: "home")
        }
        public static func policy(id: String) -> NavigationIntent {
            .init(feature: "insurance", screen: "policy", params: ["id": id])
        }
    }

    public enum DoctorConsult {
        public static func home() -> NavigationIntent {
            .init(feature: "doctorConsult", screen: "home")
        }
    }

    public enum Marketplace {
        public static func home() -> NavigationIntent {
            .init(feature: "marketplace", screen: "home")
        }
    }
}
