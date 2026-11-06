//
//  CacheError.swift
//  AppModules
//
//  Created by Asyst on 4/8/26.
//
import Foundation

enum CacheHitError: Error {
    case hit(Data)
    
    var hitData: Data {
           switch self {
           case .hit(let data): return data
           }
     }
}
