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

final class MusicPlayer: NSObject, ObservableObject {

    static let shared = MusicPlayer()

    @Published var currentTrack: AudioTrack?
    @Published var queue: [AudioTrack] = []
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isDraggingSlider = false

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
        if let index = queue.firstIndex(of: current), index + 1 < queue.count {
            playTrack(queue[index + 1])
        }
    }

    func playPrevious() {
        guard let current = currentTrack, !queue.isEmpty else { return }
        if let index = queue.firstIndex(of: current), index - 1 >= 0 {
            playTrack(queue[index - 1])
        }
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