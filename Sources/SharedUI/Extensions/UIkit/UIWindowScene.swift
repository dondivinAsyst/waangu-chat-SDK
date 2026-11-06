//
//  UIScreen.swift
//  AppModules
//
//  Created by Don divin on 5/6/26.
//


//
//  UIWindowSceneExtensions.swift
//  WhatsAppClone
//
//  Created by Muharrem Efe Çayırbahçe on 26.01.2025.
//

import UIKit

extension UIWindowScene {
   public static var current: UIWindowScene? {
        return UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene
    }
    
  public  var screenHeight: CGFloat {
        return UIWindowScene.current?.screen.bounds.height ?? 0
    }
    
   public var screenWidth: CGFloat {
        return UIWindowScene.current?.screen.bounds.width ?? 0
    }
}
