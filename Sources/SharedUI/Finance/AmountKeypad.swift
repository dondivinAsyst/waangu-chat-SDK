//
//  AmountKeypad.swift
//  SharedUI
//
//  Saisie d'un montant : affichage et pavé.
//

import SwiftUI

// MARK: - Affichage

/// Le montant en cours de saisie, en gros et au centre.
///
/// **Affiche ce qui est saisi, sans jamais le corriger.** Les milliers sont
/// groupés pour la lecture, mais aucun arrondi ni complément n'est appliqué :
/// ce que l'utilisateur lit est exactement ce qu'il a tapé, et c'est ce qui
/// partira au devis.
public struct AmountDisplay: View {

    /// Chiffres saisis, sans séparateur — « 4000 ».
    public let digits: String

    /// Code ISO, affiché à côté du nombre.
    public let currencyCode: String

    /// Nombre de décimales de la devise. 0 pour le BIF, 2 pour le CAD.
    public let fractionDigits: Int

    /// Corps du nombre. 54 pt par défaut : c'est la valeur que l'utilisateur
    /// relit avant de confirmer, et elle doit dominer l'écran.
    public let size: CGFloat

    public init(digits: String, currencyCode: String,
                fractionDigits: Int, size: CGFloat = 54) {
        self.digits = digits
        self.currencyCode = currencyCode
        self.fractionDigits = fractionDigits
        self.size = size
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(whole)
                .font(.system(size: size, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(digits.isEmpty ? AppColors.subtitleGray.opacity(0.5)
                                                : AppColors.textPrimary)

            if let fraction {
                Text(fraction)
                    .font(.system(size: size, weight: .bold))
                    .monospacedDigit()
                    // La partie décimale non encore saisie reste grise : elle
                    // montre la forme attendue sans se faire passer pour une
                    // valeur entrée.
                    .foregroundStyle(AppColors.subtitleGray.opacity(0.55))
            }

            Text(currencyCode)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppColors.primary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel("\(whole)\(fraction ?? "") \(currencyCode)")
    }

    /// Partie entière, milliers groupés selon la locale.
    private var whole: String {
        let raw = digits.contains(".") ? String(digits.prefix(while: { $0 != "." })) : digits
        guard !raw.isEmpty else { return "0" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.locale = .current
        return formatter.string(from: NSDecimalNumber(string: raw)) ?? raw
    }

    /// Partie décimale, ou `nil` pour une devise sans décimales.
    private var fraction: String? {
        guard fractionDigits > 0 else { return nil }
        let separator = Locale.current.decimalSeparator ?? "."
        guard let dot = digits.firstIndex(of: ".") else {
            return separator + String(repeating: "0", count: fractionDigits)
        }
        let typed = String(digits[digits.index(after: dot)...])
        return separator + typed.padding(toLength: fractionDigits, withPad: "0", startingAt: 0)
    }
}

// MARK: - Pavé

/// Pavé numérique dessiné, plutôt que le clavier système.
///
/// Le clavier décimal du système remonte par-dessus l'écran et recouvre ce que
/// l'utilisateur doit voir pour décider — le bénéficiaire, son solde, le bouton
/// d'envoi. Un pavé posé dans la page laisse tout visible en permanence.
///
/// Il ne contient **que** des chiffres. Pas de touche de validation : l'envoi
/// reste un bouton distinct, à distance du pavé, pour qu'on ne l'atteigne pas
/// dans l'élan de la frappe.
public struct AmountKeypad: View {

    public enum Key: Hashable {
        case digit(Character)
        case decimal
        case delete
    }

    /// Masque la touche décimale pour les devises sans décimales.
    ///
    /// Le BIF n'en a pas : offrir un point permettrait de saisir « 4000,5 »,
    /// un montant qui n'existe pas et que le backend rejetterait après coup.
    public let allowsDecimal: Bool

    /// Hauteur d'une touche.
    ///
    /// 48 pt et non 52 : quatre rangées à 52 plus leurs gouttières prenaient
    /// près du tiers de l'écran, et le montant — ce que l'utilisateur relit
    /// avant d'envoyer — se retrouvait comprimé en haut. 48 reste au-dessus du
    /// minimum tactile de 44.
    public let keyHeight: CGFloat

    public let onKey: (Key) -> Void

    public init(allowsDecimal: Bool,
                keyHeight: CGFloat = 48,
                onKey: @escaping (Key) -> Void) {
        self.allowsDecimal = allowsDecimal
        self.keyHeight = keyHeight
        self.onKey = onKey
    }

    /// Quatre rangées. `nil` marque un emplacement vide.
    ///
    /// Sans décimale, c'est la **première** colonne de la dernière rangée qui
    /// se vide : « 0 » garde ainsi sa position centrale et l'effacement sa
    /// position à droite, aux deux endroits où le doigt les cherche.
    private var rows: [[Key?]] {
        [
            [.digit("1"), .digit("2"), .digit("3")],
            [.digit("4"), .digit("5"), .digit("6")],
            [.digit("7"), .digit("8"), .digit("9")],
            [allowsDecimal ? .decimal : nil, .digit("0"), .delete]
        ]
    }

    public var body: some View {
        VStack(spacing: 7) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 7) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, key in
                        if let key {
                            KeypadButton(key: key, height: keyHeight, action: { onKey(key) })
                        } else {
                            // Hauteur **fixe**, pas minimale : une `Color` prend
                            // toute la hauteur qu'on lui propose, et `minHeight`
                            // ne la borne pas. Dans un conteneur qui propose tout
                            // l'écran, la dernière rangée s'étirait jusqu'en bas.
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: keyHeight)
                        }
                    }
                }
            }
        }
    }
}

private struct KeypadButton: View {

    let key: AmountKeypad.Key
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                .frame(maxWidth: .infinity, minHeight: height)
                .background(AppColors.cardBackground,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(KeypadPressStyle())
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var label: some View {
        switch key {
        case .digit(let character):
            Text(String(character))
                .font(.system(size: 24, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(AppColors.textPrimary)
        case .decimal:
            Text(Locale.current.decimalSeparator ?? ".")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(AppColors.textPrimary)
        case .delete:
            Image(systemName: "delete.left")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(AppColors.textPrimary)
        }
    }

    private var accessibilityLabel: String {
        switch key {
        case .digit(let character): return String(character)
        case .decimal:              return Locale.current.decimalSeparator ?? "."
        case .delete:               return "delete"
        }
    }
}

/// Enfoncement franc : une touche qui ne répond pas se retape, et sur un montant
/// une frappe doublée se voit tout de suite.
private struct KeypadPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

// MARK: - Règles de saisie

/// Ce qu'une touche fait au montant en cours.
///
/// **Une seule implémentation, partagée par tous les écrans de saisie.**
/// L'envoi et la demande l'avaient chacun la leur, à l'identique : deux copies
/// des mêmes trois règles finissent par diverger sur la quatrième, et une
/// divergence de saisie sur un montant ne se voit qu'au débit.
public enum AmountEntry {

    /// Décimales de la devise, **pour l'affichage et la saisie uniquement**.
    ///
    /// Lue dans la base de locales et non dans le contrat financier :
    /// `CurrencyCode` tient l'exposant faisant autorité, et il vient du
    /// backend. Ici aucun calcul monétaire n'a lieu — on décide seulement s'il
    /// faut offrir une touche décimale et combien de chiffres accepter. Le
    /// montant part au devis tel que saisi, et c'est le backend qui tranche.
    public static func fractionDigits(for currencyCode: String) -> Int {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        return formatter.maximumFractionDigits
    }

    /// Applique une touche.
    ///
    /// Trois règles, et chacune ferme une saisie que le backend refuserait :
    /// pas de second séparateur, pas plus de décimales que la devise n'en a,
    /// pas de zéro de tête.
    public static func apply(_ key: AmountKeypad.Key,
                             to digits: inout String,
                             fractionDigits: Int) {
        switch key {
        case .delete:
            if !digits.isEmpty { digits.removeLast() }

        case .decimal:
            guard fractionDigits > 0, !digits.contains(".") else { return }
            digits = digits.isEmpty ? "0." : digits + "."

        case .digit(let character):
            if let dot = digits.firstIndex(of: ".") {
                let typed = digits.distance(from: digits.index(after: dot), to: digits.endIndex)
                guard typed < fractionDigits else { return }
            } else if digits == "0" {
                // « 0 » suivi d'un chiffre devient ce chiffre, pas « 05 ».
                digits = ""
            }
            digits.append(character)
        }
    }

    /// Écrit un montant pour l'affichage : milliers groupés, devise suffixée.
    ///
    /// **Un seul formatage pour toute la surface financière.** Les écrans
    /// interpolaient `\(amount) \(currency)` directement : la saisie affichait
    /// « 20 000 » et le récapitulatif « 20000 » pour le même montant, dans le
    /// même parcours. Deux écritures d'une même somme font douter de la somme.
    public static func format(_ amount: Decimal, _ currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = fractionDigits(for: currencyCode)
        formatter.locale = .current
        let text = formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
        return text + " " + currencyCode
    }

    /// Même chose depuis une saisie brute.
    public static func format(_ digits: String, _ currencyCode: String) -> String {
        format(Decimal(string: digits) ?? 0, currencyCode)
    }

    /// Même chose depuis des **unités mineures**.
    ///
    /// L'exposant vient de la base de locales, pas du contrat : `CurrencyCode`
    /// tient celui qui fait autorité et il vient du backend. Ici rien n'est
    /// calculé — on remet seulement la virgule pour l'affichage. Ne jamais
    /// réinjecter le résultat dans un calcul.
    ///
    /// `Int64` et non `Int` : c'est le type que les rails de paiement
    /// échangent, et celui de ``Money/minorUnits``.
    public static func format(minorUnits: Int64, _ currencyCode: String) -> String {
        let exponent = fractionDigits(for: currencyCode)
        let divisor = pow(Decimal(10), exponent)
        return format(Decimal(minorUnits) / divisor, currencyCode)
    }

    /// `true` si la saisie ne représente aucun montant envoyable.
    ///
    /// Vide et zéro sont traités ensemble : les distinguer laisserait le bouton
    /// actif sur « 0 », qui échouerait au devis.
    public static func isBlank(_ digits: String) -> Bool {
        (Decimal(string: digits) ?? 0) <= 0
    }
}
