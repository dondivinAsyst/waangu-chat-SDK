import Foundation
import SwiftUI
import WaanguCoreKit

class FileUploadRepository: FileUploadRepositoryProtocol {
    private let httpDataSource: HTTPFileUploadDataSourceProtocol
    private let uploadClient: UploadClientProtocol
    private let mapper: FileUploadMapper
    private let logger: AppLoggerProtocol
    
    init(
        httpDataSource: HTTPFileUploadDataSourceProtocol,
        uploadClient: UploadClientProtocol,
        mapper: FileUploadMapper,
        logger: any AppLoggerProtocol = AppLogger.shared
    ) {
        self.httpDataSource = httpDataSource
        self.uploadClient = uploadClient
        self.mapper = mapper
        self.logger = logger
    }
    
    func getPresignedUploadURLs(for request: FileUploadRequest) async -> Result<PresignedUpload, AppError> {
        await logger.log("✅ about to request presigned URL for: \(request)", level: .debug)
        do {
            // Validation de la taille du fichier
            guard mapper.validateFileSize(request.fileSize ?? 0) else {
//                throw AppError.uploadError("Fichier trop volumineux. Maximum: 10MB")
                throw AppError.unknown("Fichier trop volumineux. Maximum: 10MB")
            }
            
            let presignedRequest = mapper.toPresignedURLRequest(from: request)
            let response = try await httpDataSource.getPresignedURL(presignedRequest)
            
            guard response.isSuccess else {
                throw AppError.unknown("Échec récupération presigned URL: \(response.message ?? "unknown error")")
            }
            
            let presignedUpload = mapper.toDomain(from: response)

            #if DEBUG
            // S3 keys a multipart upload by bucket + key + uploadId. A `NoSuchUpload`
            // on complete means that triple did not resolve, so both halves of the
            // exchange have to be visible to tell which part is wrong. This is the
            // half the server gave us — note `tenantId` and `location`, which the
            // complete request does not send back.
            await logger.log(
                """
                📥 initiate-with-presigned → uploadId=\(presignedUpload.uploadId) \
                key=\(presignedUpload.key) parts=\(presignedUpload.parts.count) \
                tenantId=\(response.data?.tenantId ?? "nil") \
                location=\(response.data?.location ?? "nil") \
                filename=\(response.data?.filename ?? "nil")
                """,
                level: .debug
            )
            #endif

            await logger.log("✅ Presigned URL obtenue pour: \(request.fileName)", level: .info)
            
            return .success(presignedUpload)
            
        } catch let error as AppError {
            await logger.log("❌ Erreur récupération presigned URL: \(error)", level: .error)
            return .failure(error)
        }
        catch {
            await logger.log("❌ Erreur inattendue récupération presigned URL: \(error)", level: .error)
            return .failure(.unknown(error.localizedDescription))
        }
    }
    // MARK: version 1 foreground
//    func uploadFile(to presignedPart: PresignedURLPart, fileData: Data) async -> Result<String, AppError> {
//        guard let url = URL(string: presignedPart.url) else {
//            return .failure(.uploadError("Invalid URL"))
//        }
//
//        var request = URLRequest(url: url)
//        request.httpMethod = "PUT"
//        request.httpBody = fileData
//
//        do {
//            let (_, response) = try await URLSession.shared.data(for: request)
//            guard let httpResponse = response as? HTTPURLResponse,
//                  httpResponse.statusCode == 200 else {
//                return .failure(.uploadError("Upload failed"))
//            }
//
//            let eTag = httpResponse.value(forHTTPHeaderField: "ETag") ?? ""
//            if eTag.isEmpty { return .failure(.uploadError("Missing ETag")) }
//            return .success(eTag)
//        } catch {
//            return .failure(.uploadError(error.localizedDescription))
//        }
//    }
    // MARK: Version 2 - Foreground upload (background sessions inject Transfer-Encoding: chunked which breaks MinIO presigned signatures)
    
    func uploadFile(to presignedPart: PresignedURLPart, fileData: Data, partNumber: Int) async -> Result<String, AppError> {

        guard let url = URL(string: presignedPart.uploadUrl) else {
            return .failure(.unknown(ChatErrorStrings.invalidURL))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        // Only content-length + host are in X-Amz-SignedHeaders — set Content-Length
        // explicitly and add nothing else. Background sessions add Transfer-Encoding: chunked
        // which isn't signed, causing MinIO to reject with 403.
        request.setValue("\(presignedPart.contentLength)", forHTTPHeaderField: "Content-Length")

        do {
            let (_, response) = try await URLSession.shared.upload(for: request, from: fileData)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.unknown("No HTTP response"))
            }

            guard httpResponse.statusCode == 200 else {
                return .failure(.unknown("Upload failed (\(httpResponse.statusCode))"))
            }

            let eTag = httpResponse.value(forHTTPHeaderField: "ETag")
                ?? httpResponse.value(forHTTPHeaderField: "etag")
                ?? ""

            guard !eTag.isEmpty else {
                return .failure(.unknown(ChatErrorStrings.uploadIncomplete))
            }

            return .success(eTag)

        } catch {
            return .failure(.unknown(error.localizedDescription))
        }
    }
    




    // MARK: - Main Upload with Retry
    
    func prepareImageData(_ fileData: Data) -> Data {
           if let image = UIImage(data: fileData),
              let jpegData = image.jpegData(compressionQuality: 0.9) {
               return jpegData
           }
           return fileData
       }
    
    func uploadFileWithRetry(
        for request: FileUploadRequest,
        fileData: Data,
        maxRetries: Int = 3
    ) async -> Result<String, AppError> {
        debugLog("✅ fileUpload request: \(request)")
        var lastError: AppError?
        
        // Do NOT re-encode the image — the presigned URLs are signed for the original
        // file size. Re-encoding changes the byte count and will cause 403 on upload.
        let safeFileData = fileData
        
        for attempt in 1...maxRetries {
            let presignedResult = await getPresignedUploadURLs(for: request)
            
            switch presignedResult {
            case .success(let presignedUpload):
                var completedParts: [CompletedPart] = []
                
                // Sort parts to ensure correct order
                let sortedParts = presignedUpload.parts.sorted { $0.partNumber < $1.partNumber }
                
                for part in sortedParts {
                    // part.start and part.end are both inclusive byte indices from the server.
                    // safeSlice uses an exclusive upper bound, so pass end + 1.
                    // This ensures partData.count == part.contentLength, matching the signed Content-Length.
                    let partData = safeFileData.safeSlice(from: part.start, to: part.end + 1)
                    
                    var eTag: String? = nil

                    // `partLoop` is load-bearing. This was a bare `break` inside the
                    // switch, which leaves the *switch* and not the loop — so every
                    // part was uploaded `maxRetries` times whether or not the first
                    // attempt worked. Three times the bytes and three times the
                    // duration on every send, and if a later attempt failed the ETag
                    // kept here no longer described what S3 held, which fails the
                    // finalize.
                    partLoop: for partAttempt in 1...maxRetries {
                        let result = await uploadFile(to: part, fileData: partData,partNumber: part.partNumber)
                        switch result {
                        case .success(let returnedETag):
                            eTag = returnedETag
                            break partLoop
                        case .failure(let error):
                            lastError = error
                            debugLog("❌ this was error while uploading part  \(error)")
                            if partAttempt < maxRetries {
                                try? await Task.sleep(nanoseconds: UInt64(partAttempt) * 2_000_000_000)
                            }
                        }
                    }
                    
                    guard let eTag = eTag else {
                        return .failure(lastError ?? .unknown(ChatErrorStrings.uploadPartFailed))
                    }
                    
                    completedParts.append(
                        CompletedPart(etag: eTag, partNumber: part.partNumber)
                    )
                }
                
                // Verify total uploaded size
                let totalUploaded = completedParts.count // Optionally sum partData.count if you want
                debugLog("✅ Finished uploading all parts. Total parts: \(totalUploaded)")
                
                // Finalize upload
                let finalizeUpload = CompleteMultipartUpload(
                    key: presignedUpload.key,
                    uploadId: presignedUpload.uploadId,
                    parts: completedParts
                )
                
                return await finalizeMultipartUpload(dto: finalizeUpload)
                
            case .failure(let error):
                lastError = error
                if attempt < maxRetries {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000)
                }
            }
        }
        
        return .failure(lastError ?? .unknown("Upload failed after retries"))
    }
    
    
    

//    func uploadFileWithRetry(
//        for request: FileUploadRequest,
//        fileData: Data,
//        maxRetries: Int = 3
//    ) async -> Result<String, AppError> {
//
//        var lastError: AppError?
//
//        for attempt in 1...maxRetries {
//
//            let presignedResult = await getPresignedUploadURLs(for: request)
//
//            switch presignedResult {
//            case .success(let presignedUpload):
//
//                var completedParts: [CompletedPart] = []
//
//                // Upload each part
//                for part in presignedUpload.parts {
//
//                    let partData = fileData.subdata(in: part.start..<min(part.end + 1, fileData.count))
//                    var eTag: String? = nil
//
//                    for partAttempt in 1...maxRetries {
//                        let result = await uploadFile(to: part, fileData: partData)
//                        await logger.log("❌✅ finishes to upload part URL obtenue pour: \(result)", level: .info)
//                        switch result {
//                        case .success(let returnedETag):
//                            eTag = returnedETag
//                            break
//                        case .failure(let error):
//                            lastError = error
//                            if partAttempt < maxRetries {
//                                try? await Task.sleep(nanoseconds: UInt64(partAttempt) * 2_000_000_000)
//                            }
//                        }
//                    }
//
//                    guard let eTag = eTag else {
//                        return .failure(lastError ?? .uploadError("Failed to upload part"))
//                    }
//
//                    completedParts.append(
//                        CompletedPart(ETag: eTag, PartNumber: part.partNumber)
//                    )
//                }
//
//                // All parts uploaded → finalize
//                let finalizeUpload = CompleteMultipartUpload(
//                    objectName: presignedUpload.objectName,
//                    uploadId: presignedUpload.uploadId,
//                    parts: completedParts
//                )
//
//                return await finalizeMultipartUpload(dto: finalizeUpload)
//
//            case .failure(let error):
//                lastError = error
//                if attempt < maxRetries {
//                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000)
//                }
//            }
//        }
//
//        return .failure(lastError ?? .uploadError("Upload failed after retries"))
//    }
    
    func finalizeMultipartUpload(dto: CompleteMultipartUpload) async -> Result<String, AppError> {
        let completeUploadRequest = mapper.toUploadCompleteRequest(from: dto)

        #if DEBUG
        // The body verbatim — the same dictionary the endpoint serialises. Worth
        // reading for three things: whether `key` and `uploadId` match the initiate
        // above, whether the part entries are spelled the way the server binds them
        // (`etag`/`partNumber` here, `ETag`/`PartNumber` in the legacy code below),
        // and whether the ETags still carry the quotes MinIO returns them with.
        if let body = try? completeUploadRequest.toDictionary() {
            await logger.log("📤 multipart/complete body: \(body)", level: .debug)
        }
        #endif
        
        do {
            let response: CompleteUploadResponse = try await httpDataSource.completeUploadFile(completeUploadRequest)
            guard response.isSuccess else {
                throw AppError.unknown("Complete upload failed: \(response.message ?? "")")
            }
            await logger.log("✅ file upload has been completed : \(response)", level: .info)
            return .success(response.data?.downloadUrl ?? "")
        } catch {
            // Map the caught Error to your domain AppError
            let appError: AppError
            if let appErr = error as? AppError {
                appError = appErr
            } else {
                // Adjust this mapping to match your AppError cases
                appError = .networkError(error.localizedDescription) // or .unknown(error) or a specific case
            }
            await logger.log("❌ finalizeMultipartUpload failed: \(error)", level: .error)
            return .failure(appError)
        }
    }


//    func uploadFileWithRetry(
//        for request: FileUploadRequest,
//        fileData: Data,
//        maxRetries: Int = 3
//    ) async -> Result<String, AppError> {
//        
//        var lastError: AppError?
//        
//        for attempt in 1...maxRetries {
//            await logger.log("🔄 Tentative d'upload \(attempt)/\(maxRetries) pour: \(request.fileName)", level: .debug)
//            
//            // Step 1: Get presigned URLs for all parts
//            let presignedResult = await getPresignedUploadURLs(for: request)
//            await logger.log("🔄 presidnedResult \(presignedResult) pour: \(request.fileName)", level: .debug)
//            switch presignedResult {
//            case .success(let presignedUpload):
//                var allPartsUploaded = true
//                
//                // Step 2: Upload each part individually
//                for part in presignedUpload.parts {
//                    var partUploaded = false
//                    
//                    for partAttempt in 1...maxRetries {
//                        let partData = fileData.subdata(in: part.start..<min(part.end + 1, fileData.count))
//                        let uploadResult = await uploadFile(to: part, fileData: partData)
//                        
//                        switch uploadResult {
//                        case .success:
//                            partUploaded = true
//                            await logger.log("🔄 uploaded \(uploadResult) pour: \(request.fileName)", level: .debug)
//                            break
//                        case .failure(let error):
//                            lastError = error
//                            await logger.log("🔄 ⚠️ Échec upload part \(part.partNumber), tentative \(partAttempt)/\(maxRetries): \(error)", level: .warning)
//                            if partAttempt < maxRetries {
//                                try? await Task.sleep(nanoseconds: UInt64(partAttempt * 2) * 1_000_000_000)
//                            }
//                        }
//                        
//                        if partUploaded { break }
//                    }
//                    
//                    if !partUploaded {
//                        allPartsUploaded = false
//                        break
//                    }
//                }
//                
//                if allPartsUploaded {
//                    return .success("upladed successfully")
//                } else if attempt < maxRetries {
//                    try? await Task.sleep(nanoseconds: UInt64(attempt * 2) * 1_000_000_000)
//                }
//                
//            case .failure(let error):
//                lastError = error
//                if attempt < maxRetries {
//                    try? await Task.sleep(nanoseconds: UInt64(attempt * 2) * 1_000_000_000)
//                }
//            }
//        }
//        
//        return .failure(lastError ?? .uploadError("Échec upload après \(maxRetries) tentatives"))
//    }

    
//    func uploadFileWithRetry(for request: FileUploadRequest, fileData: Data, maxRetries: Int = 3) async -> Result<String, AppError> {
//        var lastError: AppError?
//        
//        for attempt in 1...maxRetries {
//            await logger.log("🔄 Tentative d'upload \(attempt)/\(maxRetries) pour: \(request.fileName)", level: .debug)
//            
//            // Étape 1: Obtenir le presigned URL
//            let presignedURLResult = await getPresignedUploadURLs(for: request)
//            
//            switch presignedURLResult {
//            case .success(let presignedURL):
//                // Étape 2: Upload du fichier
//                let uploadResult = await uploadFile(to: presignedURL, fileData: fileData)
//                
//                switch uploadResult {
//                case .success(let fileUrl):
//                    return .success(fileUrl)
//                case .failure(let error):
//                    lastError = error
//                    if attempt == maxRetries {
//                        return .failure(error)
//                    }
//                    // Attendre avant de réessayer (backoff exponentiel)
//                    try? await Task.sleep(nanoseconds: UInt64(attempt * 2) * 1_000_000_000)
//                }
//                
//            case .failure(let error):
//                lastError = error
//                if attempt == maxRetries {
//                    return .failure(error)
//                }
//                // Attendre avant de réessayer
//                try? await Task.sleep(nanoseconds: UInt64(attempt * 2) * 1_000_000_000)
//            }
//        }
//        
//        return .failure(lastError ?? .uploadError("Échec upload après \(maxRetries) tentatives"))
//    }
    
}


extension Data {
    func safeSlice(from start: Int, to end: Int) -> Data {
        // Clamp to non-negative using the global functions explicitly
        let s = Swift.max(0, start)
        let e = Swift.max(0, end)

        // Auto-correct reversed ranges (e.g., start > end)
        let lower = Swift.min(s, e)
        let upper = Swift.max(s, e)

        // Clamp to bounds of Data
        let clampedLower = Swift.min(Swift.max(0, lower), self.count)
        let clampedUpper = Swift.min(Swift.max(0, upper), self.count)

        // Empty if invalid or equal
        guard clampedLower < clampedUpper else { return Data() }

        // Create range safely
        let range = clampedLower..<clampedUpper
        return self.subdata(in: range)
    }
}
