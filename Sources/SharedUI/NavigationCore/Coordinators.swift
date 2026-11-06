//
//  Coordinators.swift
//  AppModules
//
//  Created by Asyst on 3/27/26.
//
import SwiftUI

@MainActor
public protocol SubCoordinating: ObservableObject {
    var path: NavigationPath { get set }
    func start()
}
