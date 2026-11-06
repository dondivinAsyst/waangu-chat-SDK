//
//  TimeInterval+Extension.swift
//  AppModules
//
//  Created by Don divin on 5/6/26.
//



import Foundation

extension TimeInterval {
  public  var formatElapsedTime: String {
        let minutes = Int(self) / 60
        let seconds = Int(self) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
   public static var stubTimeInterval: TimeInterval {
        return TimeInterval()
    }
}
