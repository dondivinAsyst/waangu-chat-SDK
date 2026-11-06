import Foundation
import WaanguCoreKit

protocol FileUploadRepositoryProtocol {
    func getPresignedUploadURLs(for request: FileUploadRequest) async -> Result<PresignedUpload, AppError>
    
    func uploadFile(to presignedPart: PresignedURLPart, fileData: Data,partNumber:Int) async -> Result<String, AppError>
    
    func uploadFileWithRetry(for request: FileUploadRequest, fileData: Data, maxRetries: Int) async -> Result<String, AppError>
}
