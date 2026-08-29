//
//  MusicService.swift
//  OpenVK for iOS
//
//  Сервис для работы с музыкальными методами OpenVK API
//  (audio.get, audio.getPopular, audio.getFeed, audio.search).
//

import Foundation
import SwiftUI

protocol MusicServiceProtocol {
    func fetchMyAudios(ownerID: Int, offset: Int, count: Int, completion: @escaping (Result<[AudioTrack], Error>) -> Void)
    func fetchPopular(offset: Int, count: Int, completion: @escaping (Result<[AudioTrack], Error>) -> Void)
    func fetchNew(offset: Int, count: Int, completion: @escaping (Result<[AudioTrack], Error>) -> Void)
    func search(query: String, offset: Int, count: Int, completion: @escaping (Result<[AudioTrack], Error>) -> Void)
    func addToMyMusic(ownerID: Int, audioID: Int, completion: @escaping (Result<Void, Error>) -> Void)
    func removeFromMyMusic(ownerID: Int, audioID: Int, completion: @escaping (Result<Void, Error>) -> Void)
}

final class MusicService: MusicServiceProtocol {

    static let shared = MusicService()

    private let colors: [Color] = [.appAccent, .blue, .purple, .orange, .pink, .indigo, .teal]

    private init() {}

    // MARK: - Audio.get (аудиозаписи пользователя)
    func fetchMyAudios(ownerID: Int, offset: Int = 0, count: Int = 100, completion: @escaping (Result<[AudioTrack], Error>) -> Void) {
        var params: [String: String] = [
            "count": "\(count)",
            "offset": "\(offset)"
        ]
        if ownerID > 0 {
            params["owner_id"] = "\(ownerID)"
        }
        call(method: "audio.get", parameters: params, completion: completion)
    }

    // MARK: - Audio.getPopular
    func fetchPopular(offset: Int = 0, count: Int = 100, completion: @escaping (Result<[AudioTrack], Error>) -> Void) {
        call(
            method: "audio.getPopular",
            parameters: ["count": "\(count)", "offset": "\(offset)"],
            completion: completion
        )
    }

    // MARK: - Audio.getFeed (новинки)
    func fetchNew(offset: Int = 0, count: Int = 100, completion: @escaping (Result<[AudioTrack], Error>) -> Void) {
        call(
            method: "audio.getFeed",
            parameters: ["count": "\(count)", "offset": "\(offset)"],
            completion: completion
        )
    }

    // MARK: - Audio.search
    func search(query: String, offset: Int = 0, count: Int = 50, completion: @escaping (Result<[AudioTrack], Error>) -> Void) {
        let params: [String: String] = [
            "q": query,
            "count": "\(count)",
            "offset": "\(offset)",
            "sort": "2"
        ]
        call(method: "audio.search", parameters: params, completion: completion)
    }

    // MARK: - Audio.add (добавить трек к себе)
    func addToMyMusic(ownerID: Int, audioID: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        APIClient.shared.call(
            method: "audio.add",
            parameters: [
                "audio_id": "\(audioID)",
                "owner_id": "\(ownerID)"
            ],
            httpMethod: "GET",
            as: String.self
        ) { (result: Result<String, APIError>) in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Audio.delete (убрать трек у себя)
    func removeFromMyMusic(ownerID: Int, audioID: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        APIClient.shared.call(
            method: "audio.delete",
            parameters: [
                "audio_id": "\(audioID)",
                "owner_id": "\(ownerID)"
            ],
            httpMethod: "GET",
            as: Int.self
        ) { (result: Result<Int, APIError>) in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Generic request

    private func call(method: String, parameters: [String: String], completion: @escaping (Result<[AudioTrack], Error>) -> Void) {
        APIClient.shared.call(
            method: method,
            parameters: parameters,
            httpMethod: "GET",
            as: VKSearchGenericResponse<VKSearchAudioItem>.self
        ) { [weak self] (result: Result<VKSearchGenericResponse<VKSearchAudioItem>, APIError>) in
            switch result {
            case .success(let response):
                let mapped = self?.mapAudios(response.items ?? []) ?? []
                completion(.success(mapped))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Mapping

    private func mapAudios(_ items: [VKSearchAudioItem]) -> [AudioTrack] {
        return items.enumerated().map { index, item -> AudioTrack in
            let durationSec = item.duration ?? 0
            let durationStr = Self.formatDuration(durationSec)
            let color = colors[index % colors.count]
            return AudioTrack(
                vkID: item.id ?? item.aid,
                ownerID: item.ownerId,
                title: item.title ?? "Аудиозапись",
                artist: item.artist ?? "Исполнитель",
                duration: durationStr,
                durationSeconds: durationSec,
                url: item.url,
                color: color,
                systemName: "music.note"
            )
        }
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