import SwiftUI
import Combine
import WaanguCoreKit

final class MediaDownloadSettingsStore: ObservableObject {

    static let shared = MediaDownloadSettingsStore()

    @AppStorage("media.wifi.photos") var wifiPhotos: Bool = true
    @AppStorage("media.wifi.audio") var wifiAudio: Bool = true
    @AppStorage("media.wifi.video") var wifiVideo: Bool = true
    @AppStorage("media.wifi.documents") var wifiDocuments: Bool = true

    @AppStorage("media.cellular.photos") var cellularPhotos: Bool = true
    @AppStorage("media.cellular.audio") var cellularAudio: Bool = true
    @AppStorage("media.cellular.video") var cellularVideo: Bool = false
    @AppStorage("media.cellular.documents") var cellularDocuments: Bool = true

    @AppStorage("media.roaming.photos") var roamingPhotos: Bool = false
    @AppStorage("media.roaming.audio") var roamingAudio: Bool = false
    @AppStorage("media.roaming.video") var roamingVideo: Bool = false
    @AppStorage("media.roaming.documents") var roamingDocuments: Bool = false

    private init() {}

    func shouldAutoDownload(type: MediaType, isWifi: Bool, isCellular: Bool, isRoaming: Bool) -> Bool {
        if isRoaming {
            return roamingSetting(for: type)
        } else if isWifi {
            return wifiSetting(for: type)
        } else if isCellular {
            return cellularSetting(for: type)
        }
        return false
    }

    private func wifiSetting(for type: MediaType) -> Bool {
        switch type {
        case .photos: return wifiPhotos
        case .audio: return wifiAudio
        case .video: return wifiVideo
        case .documents: return wifiDocuments
        }
    }

    private func cellularSetting(for type: MediaType) -> Bool {
        switch type {
        case .photos: return cellularPhotos
        case .audio: return cellularAudio
        case .video: return cellularVideo
        case .documents: return cellularDocuments
        }
    }

    private func roamingSetting(for type: MediaType) -> Bool {
        switch type {
        case .photos: return roamingPhotos
        case .audio: return roamingAudio
        case .video: return roamingVideo
        case .documents: return roamingDocuments
        }
    }

    enum MediaType {
        case photos, audio, video, documents
    }
}

@available(iOS 17.0, *)
struct MediaAutoDownloadSettingsView: View {

    @StateObject private var store = MediaDownloadSettingsStore.shared
    let translationService: (any TranslationServiceProtocol)?

    init(translationService: (any TranslationServiceProtocol)? = nil) {
        self.translationService = translationService
    }

    var body: some View {
        List {
            Section(t(ChatTranslationKeys.MEDIA_WIFI)) {
                Toggle(t(ChatTranslationKeys.MEDIA_PHOTOS), isOn: $store.wifiPhotos)
                Toggle(t(ChatTranslationKeys.MEDIA_AUDIO), isOn: $store.wifiAudio)
                Toggle(t(ChatTranslationKeys.MEDIA_VIDEO), isOn: $store.wifiVideo)
                Toggle(t(ChatTranslationKeys.MEDIA_DOCUMENTS), isOn: $store.wifiDocuments)
            }

            Section(t(ChatTranslationKeys.MEDIA_MOBILE_DATA)) {
                Toggle(t(ChatTranslationKeys.MEDIA_PHOTOS), isOn: $store.cellularPhotos)
                Toggle(t(ChatTranslationKeys.MEDIA_AUDIO), isOn: $store.cellularAudio)
                Toggle(t(ChatTranslationKeys.MEDIA_VIDEO), isOn: $store.cellularVideo)
                Toggle(t(ChatTranslationKeys.MEDIA_DOCUMENTS), isOn: $store.cellularDocuments)
            }

            Section(t(ChatTranslationKeys.MEDIA_ROAMING)) {
                Toggle(t(ChatTranslationKeys.MEDIA_PHOTOS), isOn: $store.roamingPhotos)
                Toggle(t(ChatTranslationKeys.MEDIA_AUDIO), isOn: $store.roamingAudio)
                Toggle(t(ChatTranslationKeys.MEDIA_VIDEO), isOn: $store.roamingVideo)
                Toggle(t(ChatTranslationKeys.MEDIA_DOCUMENTS), isOn: $store.roamingDocuments)
            }

            Section {
                Button(t(ChatTranslationKeys.MEDIA_RESET_DEFAULTS), role: .destructive) {
                    resetToDefaults()
                }
            }
        }
        .navigationTitle(t(ChatTranslationKeys.MEDIA_AUTO_DOWNLOAD_TITLE))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func resetToDefaults() {
        store.wifiPhotos = true; store.wifiAudio = true; store.wifiVideo = true; store.wifiDocuments = true
        store.cellularPhotos = true; store.cellularAudio = true; store.cellularVideo = false; store.cellularDocuments = true
        store.roamingPhotos = false; store.roamingAudio = false; store.roamingVideo = false; store.roamingDocuments = false
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}
