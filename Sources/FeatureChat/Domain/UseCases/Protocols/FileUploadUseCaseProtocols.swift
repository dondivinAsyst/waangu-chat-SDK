import Foundation
import WaanguCoreKit

public protocol GetPresignedURLUseCaseProtocol {
//    func execute(for request: FileUploadRequest) async -> Result<PresignedURL, AppError>
    func execute(for request: FileUploadRequest) async -> Result<PresignedUpload, AppError>
}

public protocol UploadFileUseCaseProtocol {
    func execute(for request: FileUploadRequest, fileData: Data) async -> Result<String, AppError>
}

public protocol UploadProfileImageUseCaseProtocol {
    func execute(userId: String, imageData: Data, fileName: String) async -> Result<String, AppError>
}

public protocol FileUplaodUseCasesProtocol {
    var getPresignedURLUseCase: GetPresignedURLUseCaseProtocol { get }
    var uploadFileUseCase: UploadFileUseCaseProtocol { get }
    var uploadProfileImageUseCase: UploadProfileImageUseCaseProtocol { get }
}
