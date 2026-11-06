//
//  WaanguRiskRegister.swift
//  CoreKit
//
//  Bloc 9, chapitre 70 — le registre **rempli**.
//

import Foundation

/// Les risques établis par l'audit du Bloc 9.
///
/// Un registre vide est un registre absent : `SecurityRiskRegister` savait
/// calculer une gravité, trier les bloquants et exporter du CSV, sans qu'aucun
/// risque n'y figure. Les six écarts de l'audit sont donc inscrits ici, avec
/// leur chemin d'attaque et leur propriétaire.
///
/// **Daté et non exhaustif.** Il couvre ce que l'audit a établi par lecture du
/// code ; les visites 2 à 6 du §7 n'ont pas été menées, et prétendre le
/// contraire serait la fausse complétude que le §34 interdit.
public enum WaanguRiskRegister {

    public static let register = SecurityRiskRegister(risks: [

        SecurityRisk(
            id: "G9-01", chapter: 72,
            asset: "Toutes les réponses financières",
            threat: "Interception et réécriture TLS",
            attackPath: "CA installé (profil MDM, proxy d'entreprise, Burp) → "
                + "l'application accepte la chaîne → montants, bénéficiaires et "
                + "statuts réécrits en transit",
            likelihood: 3, impact: 5, owner: "MOBILE + DEVOPS",
            controls: ["CertificatePinningDelegate", "AllowedHostsPolicy"],
            // Résiduel élevé : le mécanisme existe mais `productionPins` est
            // vide, donc rien n'est épinglé en pratique.
            residualRisk: 4
        ),

        SecurityRisk(
            id: "G9-02", chapter: 71,
            asset: "Session utilisateur",
            threat: "Refresh token exfiltré réutilisable indéfiniment",
            attackPath: "Vol du jeton → aucune rotation, aucune détection de "
                + "réutilisation → deux porteurs simultanés jusqu'à expiration. "
                + "Aggravé : le chemin de rafraîchissement sur 401 ne fait rien, "
                + "tous les middlewares rendant `nil`",
            likelihood: 3, impact: 5, owner: "BACKEND (IAM)",
            controls: ["RefreshTokenRotating (contrat + simulation, non câblé)"],
            residualRisk: 5
        ),

        SecurityRisk(
            id: "G9-03", chapter: 73,
            asset: "Intégrité du client",
            threat: "Application repackagée ou instrumentée",
            attackPath: "Frida ou binaire modifié → mêmes requêtes qu'un client "
                + "authentique → le backend ne peut pas distinguer les deux",
            likelihood: 2, impact: 5, owner: "MOBILE + SECURITY PLATFORM",
            controls: ["AppAttestService", "DeviceAttestationVerifying",
                       "DeviceIntegritySignals"],
            // Réduit : la production et la vérification sont désormais reliées ;
            // reste que le vérificateur est simulé.
            residualRisk: 3
        ),

        SecurityRisk(
            id: "G9-04", chapter: 73,
            asset: "Contenu affiché à l'écran",
            threat: "Instantané système lisible hors application",
            attackPath: "Passage en arrière-plan → iOS écrit l'instantané sur "
                + "disque → solde, bénéficiaire et QR récupérables via une "
                + "sauvegarde",
            likelihood: 4, impact: 3, owner: "MOBILE",
            controls: ["PrivacyShield", "SensitiveContentModifier"],
            residualRisk: 1
        ),

        SecurityRisk(
            id: "G9-05", chapter: 76,
            asset: "Journal d'audit",
            threat: "Suppression ou réécriture indétectable",
            attackPath: "Accès interne au stockage d'audit → retrait d'un "
                + "événement → sans chaînage, aucune trace de la suppression",
            likelihood: 2, impact: 4, owner: "BACKEND",
            controls: ["FinancialAuditEmitting", "SimulatedAuditAuthority",
                       "previousHash", "forbiddenKeys"],
            residualRisk: 3
        ),

        SecurityRisk(
            id: "G9-06", chapter: 73,
            asset: "Routes de navigation",
            threat: "Lien profond forgé ou rejoué",
            attackPath: "Lien construit par un tiers → aucune signature, aucun "
                + "nonce, aucune échéance → la première route financière ajoutée "
                + "devient exploitable sans que rien ne le signale",
            likelihood: 3, impact: 4, owner: "MOBILE + BACKEND",
            controls: ["DeepLinkValidator", "DeepLinkTrustRequirement",
                       "défaut .financial pour route inconnue"],
            residualRisk: 2
        ),

        SecurityRisk(
            id: "B8-P08", chapter: 76,
            asset: "Flux de synchronisation",
            threat: "Perte d'événements non détectée",
            attackPath: "Événement manquant entre deux pages → le curseur de "
                + "date ne le révèle pas → l'état local diverge en silence",
            likelihood: 3, impact: 3, owner: "BACKEND",
            controls: ["SequenceGuard (testé, sans appelant)"],
            residualRisk: 4
        )
    ])
}
