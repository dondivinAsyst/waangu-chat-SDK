import Foundation
import WaanguCoreKit
import WaanguNetworkKit

enum FileUploadEndpoints: APIEndpoint,EndpointPolicyProviding {
    case getPresignedURL(PresignedURLRequest)
    case completeUpload(CompleteFileUploadRequest)
  

    var path: String {
        switch self {
        case .getPresignedURL:
            return "/chat-core/media/multipart/initiate-with-presigned"
            
        case .completeUpload:
            return "/chat-core/media/multipart/complete"
            
        }
    }
    
    var method: HTTPMethod {
        switch self {
        case .getPresignedURL:
            return .post
            
        case .completeUpload:
            return .post
            
        }
    }
    
    var parameters: [String: Any]? {
        switch self {
        case .getPresignedURL(let request):
            var dict = (try? request.toDictionary()) ?? [:]
            
            // Encode fileName if needed
            if let fileName = dict[PresignedURLRequest.CodingKeys.fileName.rawValue] as? String,
               let encoded = fileName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                dict[PresignedURLRequest.CodingKeys.fileName.rawValue] = encoded
            }
            
            return dict
            
        case .completeUpload(let request):
            return (try? request.toDictionary()) ?? [:]
            
            
        }
    }
    
     var headers: [String: String]? {
         return [
             "X-Correlation-Id": CorrelationId().value,  // B59 — même règle que ChatFinanceEndpoints
             "accept": "application/json",
             "x-chat-session": CurrentSessionInfo.shared.sessionId,
             "Content-Type": "application/json"
         ]
     }
}
extension FileUploadEndpoints {
    var cachePolicy: EndpointCachePolicy { .noCache }

    var circuitBreakerProfile: CircuitBreakerProfile { .standard }

    var priority: RequestPriority { .medium }

    var timeoutPolicy: EndpointTimeoutPolicy { .standard }

    /// `complete` consumes its upload id: S3 finishes the multipart upload and
    /// forgets it, so a second call gets "the specified multipart upload does not
    /// exist" and a 500 for a request that had in fact succeeded. Recovery is a
    /// fresh `initiate` and a fresh set of parts, never a repeat of this call.
    ///
    /// `initiate` is repeatable — a retry just mints another upload id — so it
    /// keeps the retries that get a media send through a flaky connection.
    var isIdempotent: Bool {
        switch self {
        case .getPresignedURL:  return true
        case .completeUpload:   return false
        }
    }

    var rateLimitPolicy: RateLimitPolicy { .relaxed }
}
