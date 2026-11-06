//
//  ErrorMapperProtocol.swift
//  AppModules
//
//  Created by Asyst on 3/23/26.
//

//
// Protocole générique de mapping d'erreurs techniques → AppError domaine.
// Zéro dépendance sur NetworkKit ou tout autre module concret.
//
// L'implémentation concrète (APIErrorMapper) vit dans NetworkKit :
//   NetworkKit/Error/APIErrorMapper.swift
//
// C'est NetworkKit qui connaît APIError — pas CoreKit.

import Foundation

/// Contrat générique de mapping erreur technique → erreur domaine.
///
/// Usage dans FeatureDependencies :
/// ```swift
/// public let errorMapper: any ErrorMapperProtocol
/// ```
///
/// Usage dans un repository :
/// ```swift
/// } catch let error as APIError {
///     throw errorMapper.map(error)   // APIError → AppError
/// }
/// ```
public protocol ErrorMapperProtocol: Sendable {

    /// Mappe n'importe quelle erreur vers une `AppError` domaine.
    /// Les implémentations concrètes font un cast interne vers leur type d'erreur.
    func map(_ error: Error) -> AppError
}
