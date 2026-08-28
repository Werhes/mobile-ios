//
//  MusicViewModel.swift
//  OpenVK for iOS
//

import SwiftUI
import Combine

enum MusicSection: String, CaseIterable, Identifiable {
    case myMusic = "Моя музыка"
    case popular = "Популярное"
    case new = "Новинки"

    var id: String { rawValue }
}

enum MusicAlert: Identifiable {
    case added
    case error(String)

    var id: String {
        switch self {
        case .added: return "added"
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

    var currentUserID: Int {
        AuthService.shared.currentUser?.uid ?? 0
    }

    func addToMyMusic(_ track: AudioTrack) {
        guard let ownerID = track.ownerID, let audioID = track.vkID else { return }
        service.addToMyMusic(ownerID: ownerID, audioID: audioID) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.activeAlert = .added
                case .failure(let error):
                    self?.activeAlert = .error(error.localizedDescription)
                }
            }
        }
    }

    func load() {
        isLoading = tracks.isEmpty
        errorMessage = nil

        switch selectedSection {
        case .myMusic:
            service.fetchMyAudios(ownerID: currentUserID) { [weak self] in self?.handle($0) }
        case .popular:
            service.fetchPopular { [weak self] in self?.handle($0) }
        case .new:
            service.fetchNew { [weak self] in self?.handle($0) }
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