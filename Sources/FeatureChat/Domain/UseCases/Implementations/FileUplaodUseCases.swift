
import Foundation
import WaanguCoreKit

//class GetPresignedURLUseCase: GetPresignedURLUseCaseProtocol {
//    private let repository: FileUploadRepositoryProtocol
//    
//    init(repository: FileUploadRepositoryProtocol) {
//        self.repository = repository
//    }
//    
//    func execute(for request: FileUploadRequest) async -> Result<PresignedURL, AppError> {
//        
//        await repository.getPresignedURL(for: request)
//    }
//}
class GetPresignedURLUseCase: GetPresignedURLUseCaseProtocol {
    private let repository: FileUploadRepositoryProtocol
    
    init(repository: FileUploadRepositoryProtocol) {
        self.repository = repository
    }
    
    func execute(for request: FileUploadRequest) async -> Result<PresignedUpload, AppError> {
        
        await repository.getPresignedUploadURLs(for: request)
    }
}

class UploadFileUseCase: UploadFileUseCaseProtocol {
    private let repository: FileUploadRepositoryProtocol
    init(repository: FileUploadRepositoryProtocol) {
        self.repository = repository
    }
    func execute(for request: FileUploadRequest, fileData: Data) async -> Result<String, AppError> {
        await repository.uploadFileWithRetry(for: request, fileData: fileData, maxRetries: 3)
    }
}

class UploadProfileImageUseCase: UploadProfileImageUseCaseProtocol {
    private let repository: FileUploadRepositoryProtocol
    
    init(repository: FileUploadRepositoryProtocol) {
        self.repository = repository
    }
    
    func execute(userId: String, imageData: Data, fileName: String) async -> Result<String, AppError> {
        let request = FileUploadRequest(
            fileName: fileName,
            fileType: "image",
            fileSize: imageData.count,
            folder: .profilePicture
        )
        
        return await repository.uploadFileWithRetry(for: request, fileData: imageData, maxRetries: 3)
    }
}





class FileUplaodUseCases: FileUplaodUseCasesProtocol {
    let getPresignedURLUseCase: GetPresignedURLUseCaseProtocol
    let uploadFileUseCase: UploadFileUseCaseProtocol
    let uploadProfileImageUseCase: UploadProfileImageUseCaseProtocol
    
    init(repository: FileUploadRepositoryProtocol) {
        self.getPresignedURLUseCase = GetPresignedURLUseCase(repository: repository)
        self.uploadFileUseCase = UploadFileUseCase(repository: repository)
        self.uploadProfileImageUseCase = UploadProfileImageUseCase(repository: repository)
    }
}
