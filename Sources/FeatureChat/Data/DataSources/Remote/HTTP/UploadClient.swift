import Foundation
import WaanguCoreKit

protocol UploadClientProtocol {
    func uploadFile(to url: String, fileData: Data, mimeType: String) async throws
}

class UploadClient: UploadClientProtocol {
    private let logger: any AppLoggerProtocol
    private let session: URLSession
    
    init(logger: any AppLoggerProtocol = AppLogger.shared, session: URLSession = .shared) {
        self.logger = logger
        self.session = session
    }
    
    func uploadFile(to url: String, fileData: Data, mimeType: String) async throws {
        guard let uploadURL = URL(string: url) else {
            throw AppError.unknown("URL d'upload invalide") // ✅ MAINTENANT ÇA FONCTIONNE
        }
        
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue("\(fileData.count)", forHTTPHeaderField: "Content-Length")
        
        await logger.log("⬆️ Upload du fichier (\(fileData.count) bytes) vers: \(uploadURL.host ?? "?")", level: .debug)
        
        let (data, response) = try await session.upload(for: request, from: fileData)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.unknown("Réponse invalide du serveur d'upload") // ✅ MAINTENANT ÇA FONCTIONNE
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Erreur inconnue"
            throw AppError.unknown("Échec upload: HTTP \(httpResponse.statusCode) - \(errorMessage)") // ✅ MAINTENANT ÇA FONCTIONNE
        }
        
        await logger.log("✅ Upload réussi - Status: \(httpResponse.statusCode)", level: .info)
    }
}
