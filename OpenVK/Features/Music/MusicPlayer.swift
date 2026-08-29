//
//  MusicPlayer.swift
//  OpenVK for iOS
//
//  Плеер музыкального раздела. Синглтон на базе VLCKit,
//  поддерживает воспроизведение потоковых аудио из OpenVK.
//

import Foundation
import Combine
import VLCKit
import AVFoundation

enum RepeatMode: Int {
    case off, all, one
}

final class MusicPlayer: NSObject, ObservableObject {

    static let shared = MusicPlayer()

    @Published var currentTrack: AudioTrack?
    @Published var queue: [AudioTrack] = []
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isDraggingSlider = false
    @Published var repeatMode: RepeatMode = .off
    @Published var shuffleEnabled = false

    private let player = VLCMediaPlayer()

    private override init() {
        super.init()
        player.delegate = self
    }

    var hasCurrentTrack: Bool {
        currentTrack != nil
    }

    // MARK: - Управление воспроизведением

    func play(track: AudioTrack, in queue: [AudioTrack]) {
        self.queue = queue
        playTrack(track)
    }

    func togglePlayPause() {
        guard currentTrack != nil else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            activateAudioSession()
            player.play()
            isPlaying = true
        }
    }

    func playNext() {
        guard let current = currentTrack, !queue.isEmpty else { return }
        if repeatMode == .one {
            playTrack(current)
            return
        }
        if shuffleEnabled {
            playTrack(queue[Int.random(in: 0..<queue.count)])
            return
        }
        guard let index = queue.firstIndex(of: current) else {
            playTrack(queue[0])
            return
        }
        let nextIndex = index + 1
        if nextIndex < queue.count {
            playTrack(queue[nextIndex])
        } else if repeatMode == .all {
            playTrack(queue[0])
        }
        // repeat off + конец очереди: ничего не делаем
    }

    func playPrevious() {
        guard let current = currentTrack, !queue.isEmpty else { return }
        if repeatMode == .one {
            playTrack(current)
            return
        }
        if shuffleEnabled {
            playTrack(queue[Int.random(in: 0..<queue.count)])
            return
        }
        guard let index = queue.firstIndex(of: current) else {
            playTrack(queue[0])
            return
        }
        let prevIndex = index - 1
        if prevIndex >= 0 {
            playTrack(queue[prevIndex])
        } else if repeatMode == .all {
            playTrack(queue[queue.count - 1])
        }
    }

    func toggleShuffle() {
        shuffleEnabled.toggle()
    }

    func cycleRepeatMode() {
        repeatMode = RepeatMode(rawValue: repeatMode.rawValue + 1) ?? .off
    }

    func seek(to seconds: Double) {
        player.time = VLCTime(int: Int32(seconds * 1000))
    }

    func stop() {
        player.stop()
        currentTrack = nil
        queue = []
        isPlaying = false
        isLoading = false
        currentTime = 0
        duration = 0
    }

    // MARK: - Private

    private func playTrack(_ track: AudioTrack) {
        guard let urlString = track.url, let url = URL(string: urlString) else { return }

        if let media = VLCMedia(url: url) {
            media.addOption("--network-caching=2000")
            player.media = media

            currentTrack = track
            currentTime = 0
            duration = 0
            isLoading = true
            activateAudioSession()
            player.play()
        }
    }

    private func activateAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("Failed to activate audio session: \(error)")
        }
    }
}

// MARK: - VLCMediaPlayerDelegate

extension MusicPlayer: VLCMediaPlayerDelegate {
    func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        DispatchQueue.main.async {
            switch newState {
            case .opening, .nothingSpecial:
                self.isLoading = true
            case .playing:
                self.isLoading = false
                self.isPlaying = true
            case .paused:
                self.isLoading = false
                self.isPlaying = false
            case .stopped, .stopping, .error:
                self.isLoading = false
                self.isPlaying = false
            @unknown default:
                break
            }
        }
    }

    func mediaPlayerBufferingChanged(_ progress: Float) {
        DispatchQueue.main.async {
            self.isLoading = progress < 1.0
        }
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        DispatchQueue.main.async {
            if !self.isDraggingSlider {
                self.currentTime = Double(self.player.time.value?.doubleValue ?? 0) / 1000.0
                if let media = self.player.media {
                    self.duration = Double(media.length.value?.doubleValue ?? 0) / 1000.0
                }
            }
        }
    }
}

// MARK: - Скачанные треки и лайки

struct DownloadedTrack: Codable, Identifiable, Hashable {
    let id: UUID
    let vkID: Int
    let ownerID: Int
    let title: String
    let artist: String
    let durationSeconds: Int
    let fileName: String
}

final class OfflineTracksStore: ObservableObject {

    static let shared = OfflineTracksStore()

    @Published private(set) var downloadedTracks: [DownloadedTrack] = []
    @Published private(set) var likedIDs: Set<Int> = []

    private let tracksKey = "offline_downloaded_tracks_v1"
    private let likesKey = "liked_track_ids_v1"

    private init() {
        loadTracks()
        loadLikes()
    }

    // MARK: - Directory

    private var downloadsDirectory: URL {
        let dir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Download / offline

    func localURL(for track: AudioTrack) -> URL? {
        guard let entry = entry(for: track) else { return nil }
        return downloadsDirectory.appendingPathComponent(entry.fileName)
    }

    func isDownloaded(_ track: AudioTrack) -> Bool {
        entry(for: track) != nil
    }

    func tracks() -> [AudioTrack] {
        downloadedTracks.map { entry -> AudioTrack in
            let local = downloadsDirectory.appendingPathComponent(entry.fileName)
            return AudioTrack(
                vkID: entry.vkID,
                ownerID: entry.ownerID,
                title: entry.title,
                artist: entry.artist,
                duration: Self.formatDuration(entry.durationSeconds),
                durationSeconds: entry.durationSeconds,
                url: local.absoluteString,
                color: .appAccent,
                systemName: "arrow.down.circle.fill"
            )
        }
    }

    func download(_ track: AudioTrack, completion: @escaping (Result<Void, Error>) -> Void) {
        if isDownloaded(track) {
            completion(.success(()))
            return
        }
        guard let urlString = track.url, let url = URL(string: urlString) else {
            completion(.failure(APIError.invalidURL))
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self else { return }
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(error ?? APIError.invalidResponse))
                }
                return
            }

            let vkID = track.vkID ?? Int(Date().timeIntervalSince1970)
            let ownerID = track.ownerID ?? 0
            let safeBase = "\(ownerID)_\(vkID)"
                .replacingOccurrences(of: "[^0-9A-Za-z_.-]", with: "_", options: .regularExpression)
            let fileName = "\(safeBase).mp3"
            let dest = self.downloadsDirectory.appendingPathComponent(fileName)

            do {
                try data.write(to: dest)
                let entry = DownloadedTrack(
                    id: UUID(),
                    vkID: vkID,
                    ownerID: ownerID,
                    title: track.title,
                    artist: track.artist,
                    durationSeconds: track.durationSeconds ?? 0,
                    fileName: fileName
                )
                DispatchQueue.main.async {
                    if !self.downloadedTracks.contains(where: { $0.vkID == vkID && $0.ownerID == ownerID }) {
                        self.downloadedTracks.append(entry)
                        self.saveTracks()
                    }
                    completion(.success(()))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    func removeDownload(_ track: AudioTrack) {
        guard let entry = entry(for: track) else { return }
        try? FileManager.default.removeItem(at: downloadsDirectory.appendingPathComponent(entry.fileName))
        downloadedTracks.removeAll { $0.id == entry.id }
        saveTracks()
    }

    // MARK: - Likes

    func isLiked(_ track: AudioTrack) -> Bool {
        guard let id = track.vkID else { return false }
        return likedIDs.contains(id)
    }

    func setLiked(_ liked: Bool, for track: AudioTrack) {
        guard let id = track.vkID else { return }
        if liked { likedIDs.insert(id) } else { likedIDs.remove(id) }
        saveLikes()
    }

    // MARK: - Persistence

    private func entry(for track: AudioTrack) -> DownloadedTrack? {
        downloadedTracks.first {
            $0.vkID == (track.vkID ?? -1) && $0.ownerID == (track.ownerID ?? -1)
        }
    }

    private func loadTracks() {
        guard let data = UserDefaults.standard.data(forKey: tracksKey),
              let decoded = try? JSONDecoder().decode([DownloadedTrack].self, from: data) else {
            return
        }
        downloadedTracks = decoded
    }

    private func saveTracks() {
        if let data = try? JSONEncoder().encode(downloadedTracks) {
            UserDefaults.standard.set(data, forKey: tracksKey)
        }
    }

    private func loadLikes() {
        let ids = UserDefaults.standard.array(forKey: likesKey) as? [Int] ?? []
        likedIDs = Set(ids)
    }

    private func saveLikes() {
        UserDefaults.standard.set(Array(likedIDs), forKey: likesKey)
    }

    private static func formatDuration(_ seconds: Int) -> String {
        guard seconds > 0 else { return "0:00" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Обложки через iTunes API

final class ITunesArtworkLoader: ObservableObject {

    static let shared = ITunesArtworkLoader()

    @Published private(set) var loadedURLs: [String: URL] = [:]

    private let cache = NSCache<NSString, NSString>()

    func artworkURL(for track: AudioTrack) -> URL? {
        let key = Self.key(for: track)
        if let cached = cache.object(forKey: key as NSString), let url = URL(string: cached as String) {
            return url
        }
        return loadedURLs[key]
    }

    func load(_ track: AudioTrack) {
        let key = Self.key(for: track)
        if artworkURL(for: track) != nil { return }

        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: "\(track.artist) \(track.title)"),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = components.url else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self = self, let data = data,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let first = results.first,
                  let art100 = first["artworkUrl100"] as? String else { return }
            let art = art100.replacingOccurrences(of: "100x100", with: "600x600")
            guard let url = URL(string: art) else { return }
            DispatchQueue.main.async {
                self.cache.setObject(art as NSString, forKey: key as NSString)
                self.loadedURLs[key] = url
            }
        }.resume()
    }

    private static func key(for track: AudioTrack) -> String {
        "\(track.artist.lowercased())|\(track.title.lowercased())"
    }
}