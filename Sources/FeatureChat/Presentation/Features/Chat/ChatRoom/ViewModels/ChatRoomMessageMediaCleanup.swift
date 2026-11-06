//
//  ChatRoomMessageMediaCleanup.swift
//  FeatureChat
//

import Foundation

/// Deletes on-disk media files associated with a chat message.
enum ChatRoomMessageMediaCleanup {

    static func deleteMediaFiles(for message: MessageDataItem) {
        let codeMessage = message.codeMessage

        switch message.typeMessage {
        case .IMAGE:
            // Les images sont enregistrées en .jpg depuis `saveImageDataToDisk` ;
            // .png reste pour les anciennes. Supprimer seulement .png les laissait.
            if DiskMediaManager.shared.hasDiskImage(for: codeMessage, pathName: .CHAT) {
                DiskMediaManager.shared.deleteStoredFiles(named: ["\(codeMessage).png", "\(codeMessage).jpg"], path: .CHAT)
                #if DEBUG
                print("🗑️ Deleted image file: \(codeMessage)")
                #endif
            }

        case .VIDEO, .VIDEO_NOTE:
            if DiskMediaManager.shared.hasDiskVideo(for: codeMessage, pathName: .CHAT) {
                DiskMediaManager.shared.deleteStoredFiles(named: ["\(codeMessage).mp4"], path: .CHAT)
                #if DEBUG
                print("🗑️ Deleted video file: \(codeMessage).mp4")
                #endif
            }
            if DiskMediaManager.shared.hasDiskImage(for: codeMessage, pathName: .CHAT) {
                DiskMediaManager.shared.deleteStoredFiles(named: ["\(codeMessage).png", "\(codeMessage).jpg"], path: .CHAT)
                #if DEBUG
                print("🗑️ Deleted video thumbnail: \(codeMessage)")
                #endif
            }

        case .AUDIO, .VOICE:
            // L'audio est écrit par `saveAudioDataToDisk` sous CHAT/<id>.<ext>
            // (documents, ou caches pour les anciens) — pas sous CHAT/files/,
            // où la recherche précédente ne trouvait jamais rien.
            if let fileName = message.message.fileName {
                let ext = (fileName as NSString).pathExtension.lowercased()
                while let url = DiskMediaManager.shared.loadAudioFromDisk(fileName: codeMessage, ext: ext, pathName: .CHAT),
                      (try? FileManager.default.removeItem(at: url)) != nil {
                    #if DEBUG
                    print("🗑️ Deleted audio file: \(url.lastPathComponent)")
                    #endif
                }
            }

        case .DOCUMENT:
            if let fileName = message.message.fileName {
                let ext = (fileName as NSString).pathExtension.lowercased()
                if DiskMediaManager.shared.hasDiskFile(for: codeMessage, ext: ext, pathName: .CHAT) {
                    DiskMediaManager.shared.deleteFileFromDisk(fileName: codeMessage, ext: ext, pathName: .CHAT)
                    #if DEBUG
                    print("🗑️ Deleted document file: \(codeMessage).\(ext)")
                    #endif
                }
            }

        default:
            break
        }
    }
}
