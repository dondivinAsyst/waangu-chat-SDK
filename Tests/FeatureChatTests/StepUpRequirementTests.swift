//
//  StepUpRequirementTests.swift
//  FeatureChatTests
//
//  Tâche 11.6b — le risque local ne peut qu'élever l'exigence backend.

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit

final class StepUpRequirementTests: XCTestCase {

    private func assessment(_ level: StepUpLevel, score: Double = 0.5) -> SessionRiskAssessment {
        SessionRiskAssessment(
            score: score,
            requiredStepUp: level,
            signals: [],
            evaluatedAt: Date()
        )
    }

    // MARK: - La propriété centrale

    /// Un client compromis qui renvoie « risque nul » ne doit rien obtenir.
    /// C'est ce qui rend acceptable d'évaluer le risque sur l'appareil surveillé.
    func test_localRiskCannotLowerBackendRequirement() {
        for backend in StepUpLevel.allCases {
            let effective = StepUpRequirement.effectiveLevel(
                backendRequired: backend,
                localAssessment: assessment(.none, score: 0)
            )
            XCTAssertEqual(effective, backend, "\(backend) a été abaissé")
        }
    }

    func test_localRiskCanRaiseRequirement() {
        let effective = StepUpRequirement.effectiveLevel(
            backendRequired: .pin,
            localAssessment: assessment(.biometricAndOTP, score: 0.9)
        )
        XCTAssertEqual(effective, .biometricAndOTP)
        XCTAssertTrue(StepUpRequirement.wasRaisedLocally(
            backendRequired: .pin,
            localAssessment: assessment(.biometricAndOTP)
        ))
    }

    /// Aucune évaluation disponible → le plancher backend s'applique tel quel.
    /// Surtout pas un défaut permissif.
    func test_absentAssessmentKeepsBackendFloor() {
        XCTAssertEqual(
            StepUpRequirement.effectiveLevel(backendRequired: .fullReauth, localAssessment: nil),
            .fullReauth
        )
        XCTAssertFalse(StepUpRequirement.wasRaisedLocally(
            backendRequired: .fullReauth,
            localAssessment: nil
        ))
    }

    /// Exigences égales : pas d'élévation, donc rien à signaler.
    func test_equalLevelsAreNotReportedAsRaised() {
        XCTAssertFalse(StepUpRequirement.wasRaisedLocally(
            backendRequired: .biometric,
            localAssessment: assessment(.biometric)
        ))
    }

    /// Propriété générale, sur toutes les combinaisons : le résultat est toujours
    /// au moins le plancher backend.
    func test_effectiveLevelIsNeverBelowBackendFloor() {
        for backend in StepUpLevel.allCases {
            for local in StepUpLevel.allCases {
                let effective = StepUpRequirement.effectiveLevel(
                    backendRequired: backend,
                    localAssessment: assessment(local)
                )
                XCTAssertGreaterThanOrEqual(effective, backend)
                XCTAssertGreaterThanOrEqual(effective, local)
            }
        }
    }
}
