//
//  PresentedQRCodeViewModel.swift
//  FeatureChat
//
//  Cycle de vie d'un QR que l'utilisateur présente : émission, rotation,
//  expiration, révocation.
//

import Foundation
import WaanguCoreKit

/// Le cycle de vie d'un QR présenté, partagé par tous les écrans qui en montrent
/// un — encaissement ou identité.
///
/// Trois règles qu'aucun écran ne doit réécrire à sa façon :
///
/// - **La charge utile vient du backend.** Rien n'est composé ici : un QR
///   fabriqué côté client est un QR que n'importe qui peut fabriquer.
/// - **Il tourne.** Un QR affiché se photographie ; la rotation borne la durée
///   pendant laquelle la photo reste utilisable.
/// - **Il se révoque** à la fermeture et en arrière-plan : sortir de l'écran ne
///   doit pas laisser un code valide derrière soi.
@MainActor
final class PresentedQRCodeViewModel: ObservableObject {

    enum Phase: Equatable {
        case issuing
        case showing(PresentableQR)
        case expired
        case failed(String)
    }

    @Published private(set) var phase: Phase = .issuing
    @Published private(set) var isClosing = false
    @Published private(set) var isRotating = false

    private let presenter: any QRPresenting
    private let request: QRPresentationRequest

    init(presenter: any QRPresenting, request: QRPresentationRequest) {
        self.presenter = presenter
        self.request = request
    }

    var isWorking: Bool {
        if isClosing || isRotating { return true }
        if case .issuing = phase { return true }
        return false
    }

    func issue() async {
        phase = .issuing
        switch await presenter.issue(request) {
        case .success(let qr):
            phase = qr.isValid() ? .showing(qr) : .expired
        case .failure(let error):
            phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    /// Fait tourner ou périmer le code selon ce que le backend a fixé.
    func refreshIfNeeded(now: Date) async {
        guard !isClosing, !isRotating, case .showing(let qr) = phase else { return }
        isRotating = true
        defer { isRotating = false }
        if !qr.isValid(at: now) {
            await revokeCurrent()
            phase = .expired
        } else if qr.needsRotation(at: now) {
            // Rotation : on demande une charge utile neuve puis on révoque
            // l'ancienne. Dans cet ordre — révoquer d'abord laisserait un
            // instant sans code présentable devant quelqu'un qui attend.
            let previous = qr.id
            switch await presenter.issue(request) {
            case .success(let fresh):
                phase = .showing(fresh)
                _ = await presenter.revoke(previous)
            case .failure:
                // La rotation a échoué : on garde le code en cours jusqu'à son
                // expiration réelle plutôt que de vider l'écran.
                break
            }
        }
    }

    func revokeCurrent() async {
        guard case .showing(let qr) = phase else { return }
        _ = await presenter.revoke(qr.id)
    }

    /// Invalide le code affiché et en émet un neuf — « Réinitialiser le QR ».
    ///
    /// Après une photo prise par quelqu'un qu'on ne voulait pas : l'ancien code
    /// ne doit plus rien ouvrir.
    func reset() async {
        guard !isWorking else { return }
        await revokeCurrent()
        await issue()
    }

    /// Révoque avant fermeture. `false` si une opération est en cours : fermer
    /// en pleine rotation pourrait laisser le code neuf non révoqué.
    func prepareToClose() async -> Bool {
        guard !isWorking else { return false }
        isClosing = true
        await revokeCurrent()
        return true
    }
}
