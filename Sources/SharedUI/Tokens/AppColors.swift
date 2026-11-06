// MARK: - SharedUI/Tokens/AppColors.swift

import SwiftUI

public enum AppColors {

    // MARK: - Primary
    public static let primary = Color(light: 0x08569E, dark: 0x1A6BB5)
    public static let white = Color(light: 0xFFFFFF, dark: 0x1C1C1E)
    public static let black = Color(light: 0x000000, dark: 0xFFFFFF)
    public static let textPrimary = Color(light: 0x1C1C1E, dark: 0xE5E5EA)

    // MARK: - Background
    public static let background = Color(light: 0xFFFFFF, dark: 0x0D1117)
    public static let backgroundGradient = Color(light: 0xE6F0F8, dark: 0x121820)
    public static let bg = Color(light: 0xE6F0F8, dark: 0x1A2A3A)
   

    // MARK: - Card / Surface
    public static let cardBackground = Color(light: 0xFFFFFF, dark: 0x1C2530)

    // MARK: - Tab bar
    public static let tabBackground     = Color(light: 0xFFFFFF, dark: 0x1C2530).opacity(0.20)
    public static let tabOverlay        = Color(light: 0xF0F7FF, dark: 0x1C2530).opacity(0.06)
    public static let tabGradientStart  = Color(light: 0xD9EEFF, dark: 0x1A2A3A)
    public static let tabGradientEnd    = Color(light: 0xEAF6FF, dark: 0x1C2E3E)
    public static let tabStroke         = Color(light: 0xE6F0FF, dark: 0x2A3A50).opacity(0.10)
    public static let tabShadow         = Color(hex: 0x000000).opacity(0.12)

    // MARK: - Tab items
    public static var tabSelectedIcon: Color { iconLabel }
    public static let tabUnselectedIcon = Color.secondary
    public static let tabSelectedLabel  = Color(light: 0x111111, dark: 0xEEEEEE)
    public static let tabUnselectedLabel = Color.secondary
    public static let redTab = Color(hex: 0xFF6B9D)

    // MARK: - Center action gradient
    public static let centerGradientStart = Color(hex: 0x2673E6)
    public static let centerGradientEnd   = Color(hex: 0x1273D4)

    // MARK: - Icon / Label
    public static let iconLabel = Color(light: 0x111111, dark: 0xEEEEEE)

    // MARK: - Feature colors
    public static let sendMoney      = Color(hex: 0x12A887)
    public static let payBill        = Color(hex: 0x2673E6)
    public static let cashIn         = Color(hex: 0xE6338C)
    public static let requestMoney   = Color(hex: 0x803326)
    public static let cashCollection = Color(hex: 0x99B3D9)
    public static let checkBalance   = Color(hex: 0x2673E6)
    public static let donations      = Color(hex: 0x3399E6)

    // MARK: - Recharge
    public static let mobileTopup = Color(hex: 0x1273D4)
    public static let electricity  = Color(hex: 0xF5BA1F)
    public static let education    = Color(hex: 0x5C45ED)
    public static let water        = Color(hex: 0x12A8E6)

    // MARK: - Transport
    public static let ride    = Color(hex: 0xF5C22E)
    public static let bus     = Color(hex: 0xF56673)
    public static let flight  = Color(hex: 0xBF52F2)
    public static let hotels  = Color(hex: 0x1273D4)

    // MARK: - Food & shopping
    public static let food        = Color(hex: 0x148FE6)
    public static let marketplace = Color(hex: 0x1F75DB)
    public static let shopping    = Color(hex: 0xF28F59)
    
    public static let titleDark = Color(light: 0x111111, dark: 0xF2F2F7)
    // MARK: - Portefeuille
    //
    // Teintes propres à l'écran « Mon portefeuille ». Le fond y est neutre et
    // non le bleuté `bg` : les cartes blanches doivent s'en détacher, et un
    // fond bleuté sous une carte blanche sous une barre bleue donne trois bleus
    // qui se disputent.

    /// Fond de page du portefeuille — gris neutre, pas le bleuté général.
    public static let walletCanvas = Color(light: 0xF0F1F3, dark: 0x0D1117)

    /// Pastille de compte en devise.
    ///
    /// Le seul vert admis de l'application, et il ne décore pas : il distingue
    /// la ligne qui porte de l'argent des lignes qui portent des réglages. Tout
    /// le reste de l'écran est en ``primary``.
    public static let walletCurrency = Color(light: 0x22C55E, dark: 0x28D26A)

    /// Pastille sombre posée sur la carte d'incitation bleue.
    public static let walletPromoBadge = Color(light: 0x0A4074, dark: 0x0A4074)

    public static let subtitleGray = Color(light: 0x6B7280, dark: 0x9CA3AF)

    /// Filet de séparation entre lignes de liste.
    ///
    /// Ajouté ici plutôt qu'en `Divider()` par défaut : les listes financières
    /// posent un filet **encastré** — il commence après la gouttière d'icône —
    /// et sa teinte doit rester la même d'un écran à l'autre. Un `Divider`
    /// système change d'épaisseur et de couleur selon le conteneur.
    public static let separator = Color(light: 0xC8C7CB, dark: 0x38383A)
    public static let amountWellBackground = Color(light: 0xE8F1FB, dark: 0x2A3F5A).opacity(0.85)
    public static let chipBorder = Color(light: 0xE5E7EB, dark: 0x3A3A3C)

    // MARK: Statuts financiers — Bloc 10, chapitre 79

    /// Réussite **vérifiée**. Le primaire, jamais le vert : le vert n'est pas à
    /// nous. La couleur ne porte d'ailleurs jamais seule le sens — voir
    /// `TransactionStatusBadge`, qui l'associe toujours à un texte et une icône.
    public static var statusSuccess: Color { primary }

    /// Échec, refus, blocage. Le primaire aussi : une seule couleur dans la
    /// finance, le sens est porté par le texte et l'icône, jamais par un rouge.
    public static var statusDanger: Color { primary }

    /// Attente, expiration, hors ligne. Le primaire, pas l'orange système.
    public static var statusWarning: Color { primary }

    /// Ni succès ni échec : vérification, remboursement, annulation neutre.
    public static var statusNeutral: Color { subtitleGray }
}
