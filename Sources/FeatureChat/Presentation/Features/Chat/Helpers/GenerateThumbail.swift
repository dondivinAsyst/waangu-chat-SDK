import SwiftUI
import Photos

// Requests an inline preview (base64) and the full-res JPEG data from a PHAsset.
// The JPEG data is passed back so it can be saved to the Disk cache as-is,
// preserving the original compressed file size under the message's codeMessage key.
func generateAndSaveThumbnail(
    for asset: PHAsset,
    completion: @escaping (_ thumbnailBase64: String?, _ fullImage: UIImage?, _ fullImageJPEGData: Data?) -> Void
) {
    // Step 1: the inline preview carried on message.thumbnail.
    //
    // This is what the receiving bubble paints on its first frame, before the
    // full image has been downloaded — so it has to look like the photo and,
    // just as importantly, share its proportions. It used to be a 60×60
    // `.aspectFill` request, which crops to a square: every gallery-sent image
    // previewed as a centre-cropped square, and the bubble sized itself 1:1 and
    // then resized once the real photo arrived.
    let thumbOptions = PHImageRequestOptions()
    thumbOptions.isSynchronous = false
    thumbOptions.deliveryMode = .highQualityFormat
    thumbOptions.isNetworkAccessAllowed = true
    thumbOptions.resizeMode = .fast

    PHImageManager.default().requestImage(
        for: asset,
        targetSize: CGSize(width: ChatMediaPreviewFormat.maxDimension, height: ChatMediaPreviewFormat.maxDimension),
        contentMode: .aspectFit,
        options: thumbOptions
    ) { thumbImage, thumbInfo in
        let base64: String?
        if let t = thumbImage,
           let data = t.jpegData(compressionQuality: ChatMediaPreviewFormat.quality) {
            base64 = "data:image/jpeg;base64," + data.base64EncodedString()
        } else {
            base64 = nil
        }

        // Step 2: full-resolution original JPEG data for disk cache
        // We use requestImageDataAndOrientation to get the actual compressed JPEG file,
        // NOT requestImage which returns a decoded UIImage (much larger when saved as PNG)
        let dataOptions = PHImageRequestOptions()
        dataOptions.isSynchronous = false
        dataOptions.deliveryMode = .highQualityFormat
        dataOptions.isNetworkAccessAllowed = true

        PHImageManager.default().requestImageDataAndOrientation(
            for: asset,
            options: dataOptions
        ) { imageData, uti, _, _ in
            let jpegData: Data?
            let uiImage: UIImage?

            if let imageData = imageData {
                // If already JPEG, use as-is. Otherwise convert to JPEG.
                if uti == "public.jpeg" || uti == "public.jpg" {
                    jpegData = imageData
                } else {
                    // HEIC, PNG, etc. — convert to JPEG to get a reasonable file size
                    jpegData = UIImage(data: imageData)?.jpegData(compressionQuality: 0.9)
                }
                uiImage = UIImage(data: imageData)
            } else {
                jpegData = nil
                uiImage = nil
            }

            completion(base64, uiImage, jpegData)
        }
    }
}
