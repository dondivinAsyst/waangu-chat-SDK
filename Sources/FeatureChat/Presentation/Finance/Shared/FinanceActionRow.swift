//
//  FinanceActionRow.swift
//  FeatureChat
//
//  Un bouton d'action posé dans un formulaire.
//

import SwiftUI
import WaanguSharedUI

extension View {

    /// Retire la carte que `Form` dessine derrière une ligne.
    ///
    /// Un `CustomButton` placé dans une `Section` héritait du fond blanc et des
    /// marges de la ligne : le bouton apparaissait **enfermé dans une carte
    /// blanche**, à un emplacement où tous les autres écrans posent un bouton
    /// pleine largeur. L'effet se voyait sur quinze écrans.
    ///
    /// Modificateurs de ligne plutôt que refonte du formulaire : ces écrans
    /// rendent des champs dynamiques venus du backend, et les sortir de `Form`
    /// leur ferait perdre le comportement de liste qu'ils utilisent.
    func financeActionRow() -> some View {
        listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
    }
}
