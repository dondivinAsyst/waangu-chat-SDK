//
//  CodingUserInfoKey+Extensions.swift
//  AppModules
//
//  Created by Asyst on 3/23/26.
//

// MARK: - CoreKit/Extensions/Foundation/CodingUserInfoKey+Extensions.swift

import Foundation

public extension CodingUserInfoKey {

    /// Indique qu'un décodage se produit en arrière-plan.
    /// Permet aux décodeurs de sauter certaines validations coûteuses
    /// ou d'adapter leur comportement selon le contexte.
    static let backgroundDecoding = CodingUserInfoKey(rawValue: "backgroundDecoding")!

    /// Contexte d'environnement injecté dans les décodeurs.
    /// Utile pour adapter le parsing selon l'environnement (dev vs prod).
    static let decodingEnvironment = CodingUserInfoKey(rawValue: "decodingEnvironment")!
}
