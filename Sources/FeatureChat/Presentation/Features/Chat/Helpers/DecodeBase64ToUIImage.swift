import Foundation
import SwiftUI

func decodeBase64ToUIImage(_ raw: String) -> UIImage? {
    // Supprime le préfixe "data:image/…;base64," si présent
    let cleanedBase64: String
    if let range = raw.range(of: "base64,") {
        cleanedBase64 = String(raw[range.upperBound...])
    } else {
        cleanedBase64 = raw
    }
    
    // Décodage
    guard let data = Data(base64Encoded: cleanedBase64, options: .ignoreUnknownCharacters),
          let image = UIImage(data: data) else {
        return nil
    }
    return image
}
