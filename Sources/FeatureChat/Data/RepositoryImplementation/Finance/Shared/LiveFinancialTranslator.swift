//
//  LiveFinancialTranslator.swift
//  FeatureChat
//
//  Phase 8 — traduction d'un texte financier par Chat Core.
//

import Foundation
import NaturalLanguage
import WaanguCoreKit

/// `FinancialTranslating` sur Chat Core : `POST /hub/translation/mask`, puis
/// `POST /hub/translation/translate`.
///
/// Le serveur masque lui-même les valeurs (montants, numéros) et rend une
/// traduction qui porte encore ses jetons. Ce type vérifie que **chaque**
/// jeton est revenu avant de les rétablir : un jeton perdu, c'est un montant
/// ou un numéro que le traducteur a touché, et la traduction est refusée
/// plutôt qu'affichée (`CF_064`, côté client).
///
/// Moteur absent côté serveur : `CF_063`, et l'écran garde le texte d'origine.
struct LiveFinancialTranslator: FinancialTranslating {

    let dataSource: any RemoteChatFinanceDataSourceProtocol

    /// Le serveur n'a pas de détection : elle se fait sur l'appareil.
    func detect(_ text: String) async -> Result<LanguageDetection, FinanceError> {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first else {
            return .failure(.validation(field: "text"))
        }
        return .success(LanguageDetection(locale: language.rawValue, confidence: confidence))
    }

    func translate(_ protected: ProtectedText, to targetLocale: String,
                   glossaryVersion: String?) async -> Result<TranslatedText, FinanceError> {
        let text = protected.maskedText
        let source: String
        switch await detect(text) {
        case .success(let detection) where detection.isReliable(): source = detection.locale
        // Langue d'origine incertaine : mieux vaut ne rien traduire (§58).
        case .success:              return .failure(.validation(field: "sourceLang"))
        case .failure(let error):   return .failure(error)
        }
        let target = String(targetLocale.prefix(2)).lowercased()
        guard source != target else { return .failure(.validation(field: "targetLang")) }

        let masked: MaskedTextDTO
        switch await FinanceCoreError.capture({ try await dataSource.maskText(MaskTextRequest(text: text)) }) {
        case .success(let value): masked = value
        case .failure(let error): return .failure(error.financeError)
        }
        let translated: String
        switch await FinanceCoreError.capture({
            try await dataSource.translateText(TranslateTextRequest(text: text, sourceLang: source,
                                                                    targetLang: target))
        }) {
        case .success(let value): translated = value
        case .failure(let error): return .failure(error.financeError)
        }

        guard let restored = Self.restore(translated, tokens: masked.tokens ?? [:]) else {
            return .failure(FinanceCoreErrorCode(rawValue: "CF_064").financeError)
        }
        return .success(TranslatedText(text: restored, targetLocale: target,
                                       authority: .machine, glossaryVersion: glossaryVersion))
    }

    /// Rétablit les valeurs du serveur. `nil` si un jeton manque : la
    /// traduction a perdu une valeur protégée.
    static func restore(_ translated: String, tokens: [String: String]) -> String? {
        var output = translated
        for (token, value) in tokens {
            guard output.contains(token) else { return nil }
            output = output.replacingOccurrences(of: token, with: value)
        }
        return output
    }
}
