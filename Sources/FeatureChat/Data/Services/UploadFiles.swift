//
//  UploadLinkResponseData.swift
//  AppModules
//
//  Created by Don divin on 5/6/26.
//


//
//  UploadFiles.swift
//  Pods
//
//  Created by Asyst on 8/18/25.
//


import Foundation

public struct UploadLinkResponseData: Codable {
    let url: String
    let fileUrl: String
}

struct UploadLinkResponse: Codable {
    let status: Int
    let message: String?
    let data: UploadLinkResponseData?
}

enum APIErrorupload: Error {
    case invalidURL
    case invalidToken
    case invalidResponse
    case requestFailed(Error)
    case decodingFailed(Error)
    case serverError(status: Int, message: String?)
    case missingResponseData
}




public func requestPresignedURL(filename: String) async throws -> UploadLinkResponseData {
    
//    return  UploadLinkResponseData(url: "", fileUrl: "")

    let location = "message"
//    let location = "story"

    let baseURL = CurrentSessionInfo.shared.baseUrl
    let token = await CurrentSessionInfo.shared.currentToken()
    
   
    guard !token.isEmpty else {
        throw APIErrorupload.invalidToken
    }
    
    guard let encodedFilename = filename.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
          let url = URL(string: "\(baseURL)api/chat-setting/files-management/upload-url?location=\(location)&filename=\(encodedFilename)") else {
        throw APIErrorupload.invalidURL
    }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.timeoutInterval = 30
    
    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        
        #if DEBUG
        print("🌐 \(request.httpMethod ?? "GET") upload-url")
        #endif
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIErrorupload.invalidResponse
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase // Si votre API utilise snake_case
        
        let decodedResponse = try decoder.decode(UploadLinkResponse.self, from: data)
        
     
        switch httpResponse.statusCode {
        case 200:
            guard let responseData = decodedResponse.data else {
                throw APIErrorupload.missingResponseData
            }
            return responseData
            
        case 400...499:
            throw APIErrorupload.serverError(
                status: decodedResponse.status,
                message: decodedResponse.message ?? "Client error"
            )
            
        case 500...599:
            throw APIErrorupload.serverError(
                status: decodedResponse.status,
                message: decodedResponse.message ?? "Server error"
            )
            
        default:
            throw APIErrorupload.serverError(
                status: httpResponse.statusCode,
                message: "Unexpected status code"
            )
        }
        
    } catch let error as DecodingError {
        throw APIErrorupload.decodingFailed(error)
    } catch let error as APIErrorupload {
        throw error
    } catch {
        throw APIErrorupload.requestFailed(error)
    }
}
