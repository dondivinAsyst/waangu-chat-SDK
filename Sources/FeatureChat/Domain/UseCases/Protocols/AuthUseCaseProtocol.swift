//
//  AuthUseCaseProtocol.swift
//  AppModules
//
//  Created by Don divin on 5/20/26.
//

import Foundation

public protocol AuthenticateUseCaseProtocol {
    func execute() async -> AuthSessionInfo?
}

public protocol AuthUseCasesProtocol {
    var authenticate: AuthenticateUseCaseProtocol { get }
}

