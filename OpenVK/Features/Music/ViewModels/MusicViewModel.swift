//
//  MusicViewModel.swift
//  OpenVK for iOS
//

import SwiftUI
import Combine

enum MusicSection: String, CaseIterable, Identifiable {
    case myMusic = "Моя музыка"
    case downloaded = "Скачанное"
    case new = "Новинки"

    var id: String { rawValue }
}

enum MusicAlert: Identifiable {
    case added
    case downloaded
    case error(String)

    var id: String {
        switch self {
        case .added: return "added"
        case .downloaded: return "downloaded"
        case .error(let message): return "error-\(message)"
        }
    }
}

final class MusicViewModel: ObservableObject {

    @Published var tracks: [AudioTrack] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedSection: MusicSection = .myMusic
    @Published var activeAlert: MusicAlert?

    private let service = MusicService.shared
    private let offlineStore = OfflineTracksStore.shared

    var currentUserID: Int {
        AuthService.shared.currentUser?.uid ?? 0
    }

    func load() {
        switch selectedSection {
        case .myMusic, .new:
            isLoading = tracks.isEmpty
            errorMessage = nil
            if selectedSection == .myMusic {
                service.fetchMyAudios(ownerID: currentUserID) { [weak self] in self?.handle($0) }
            } else {
                service.fetchNew { [weak self] in self?.handle($0) }
            }
        case .downloaded:
            tracks = offlineStore.tracks()
            isLoading = false
            errorMessage = nil
        }
    }

    func search(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            load()
            return
        }
        isLoading = tracks.isEmpty
        errorMessage = nil
        service.search(query: trimmed) { [weak self] in self?.handle($0) }
    }

    // MARK: - Скачивание (офлайн)

    func isDownloaded(_ track: AudioTrack) -> Bool {
        offlineStore.isDownloaded(track)
    }

    func download(_ track: AudioTrack) {
        if isDownloaded(track) {
            activeAlert = .downloaded
            return
        }
        offlineStore.download(track) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.activeAlert = .downloaded
                    if self?.selectedSection == .downloaded {
                        self?.load()
                    }
                case .failure(let error):
                    self?.activeAlert = .error(error.localizedDescription)
                }
            }
        }
    }

    func removeDownload(_ track: AudioTrack) {
        offlineStore.removeDownload(track)
        if selectedSection == .downloaded {
            tracks = offlineStore.tracks()
        }
    }

    // MARK: - Лайки (добавить/убрать к себе)

    func isLiked(_ track: AudioTrack) -> Bool {
        offlineStore.isLiked(track)
    }

    func toggleLike(_ track: AudioTrack) {
        let store = offlineStore
        let target = !store.isLiked(track)
        guard let ownerID = track.ownerID, let audioID = track.vkID else { return }

        if target {
            service.addToMyMusic(ownerID: ownerID, audioID: audioID) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        store.setLiked(true, for: track)
                    case .failure(let error):
                        self?.activeAlert = .error(error.localizedDescription)
                    }
                }
            }
        } else {
            service.removeFromMyMusic(ownerID: ownerID, audioID: audioID) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        store.setLiked(false, for: track)
                    case .failure(let error):
                        self?.activeAlert = .error(error.localizedDescription)
                    }
                }
            }
        }
    }

    private func handle(_ result: Result<[AudioTrack], Error>) {
        isLoading = false
        switch result {
        case .success(let tracks):
            self.tracks = tracks
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}