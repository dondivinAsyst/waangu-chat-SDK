//
//  AuthRepositoryProtocol.swift
//  AppModules
//
//  Created by Don divin on 5/20/26.
//

import Foundation


public protocol AuthRepositoryProtocol: Sendable {
   func authenticate() async  -> AuthSessionInfo?
}
