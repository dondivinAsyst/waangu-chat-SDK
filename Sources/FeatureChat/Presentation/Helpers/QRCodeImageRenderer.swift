//
//  QRCodeImageRenderer.swift
//  FeatureChat
//

import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Rastérise une charge utile de QR.
enum QRCodeImageRenderer {

    /// Encode la charge utile **telle quelle**.
    ///
    /// Aucune normalisation, aucun recadrage de la chaîne : elle est signée, et
    /// la moindre retouche invaliderait la signature côté lecteur.
    static func render(_ payload: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        // Correction d'erreur haute : le code reste lisible sur un écran sale
        // ou partiellement masqué par un reflet.
        filter.correctionLevel = "H"

        guard let output = filter.outputImage else { return nil }
        // Agrandi avant rasterisation, sinon le QR sort en quelques pixels.
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
