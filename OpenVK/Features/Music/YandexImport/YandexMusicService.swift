//
//  YandexMusicService.swift
//  OpenVK for iOS
//
//  Клиент неофициального API Яндекс Музыки (api.music.yandex.net).
//  Работает с OAuth-токеном, полученным после входа через WebView.
//

import Foundation

final class YandexMusicService {

    static let shared = YandexMusicService()

    private let baseURL = URL(string: "https://api.music.yandex.net")!
    private let session: URLSession
    private let decoder = JSONDecoder()

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        // Нужен реалистичный браузерный User-Agent, иначе API может отклонять запросы.
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"
        ]
        self.session = URLSession(configuration: config)
    }

    // MARK: - Токен

    static var storedToken: String? {
        get { UserDefaults.standard.string(forKey: YandexConstants.tokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: YandexConstants.tokenKey) }
    }

    /// Обрезаем токен: в URL/JS он может попасть с пробелами или лишним мусором.
    static func cleanToken(_ raw: String?) -> String? {
        guard let raw = raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count >= 20 else { return nil }
        return trimmed
    }

    // MARK: - Аккаунт (uid)

    func fetchUid(token: String, completion: @escaping (Result<Int, Error>) -> Void) {
        request(path: "account/status", query: [:], token: token) {
            (result: Result<YandexAccountStatusResult, Error>) in
            switch result {
            case .success(let response):
                if let uid = response.account?.uid {
                    completion(.success(uid))
                } else {
                    completion(.failure(YandexError.noAccount))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Лайкнутые треки ("Мне нравится", плейлист id = 3)

    /// Возвращает полные треки «Мне нравится»:
    /// 1. GET /users/{uid}/likes/tracks → короткие треки (id)
    /// 2. GET /tracks/{ids} → полные объекты треков
    func fetchLikedTracks(token: String, uid: Int, completion: @escaping (Result<[YandexTrack], Error>) -> Void) {
        request(path: "users/\(uid)/likes/tracks", query: [:], token: token) {
            (result: Result<YandexLikesResponse, Error>) in
            switch result {
            case .success(let response):
                let ids = response.result?.library?.tracks?.map { $0.id } ?? []
                if ids.isEmpty {
                    completion(.success([]))
                } else {
                    self.fetchTracks(ids: ids, token: token, completion: completion)
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func fetchTracks(
        ids: [Int],
        token: String,
        completion: @escaping (Result<[YandexTrack], Error>) -> Void
    ) {
        let idString = ids.map(String.init).joined(separator: ",")
        request(path: "tracks/\(idString)", query: [:], token: token) {
            (result: Result<YandexTracksResponse, Error>) in
            switch result {
            case .success(let response):
                completion(.success(response.result ?? []))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Прямая ссылка на скачивание трека

    /// Возвращает прямую ссылку на MP3. Многие треки в Яндекс Музыке защищены
    /// DRM и не отдают рабочие ссылки — для них вернётся nil (трек будет пропущен).
    func fetchDownloadURL(token: String, trackId: Int, completion: @escaping (Result<String?, Error>) -> Void) {
        request(path: "tracks/\(trackId)/download-info", query: [:], token: token) {
            (result: Result<YandexDownloadInfoResponse, Error>) in
            switch result {
            case .success(let response):
                let infos = response.result ?? []
                let mp3s = infos.filter { $0.codec == "mp3" }
                let candidates = mp3s.isEmpty ? infos : mp3s
                let chosen = candidates
                    .sorted { ($0.bitrateInKbps ?? 0) > ($1.bitrateInKbps ?? 0) }
                    .first
                completion(.success(chosen?.directLink))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Скачивание аудиофайла

    func downloadTrack(from urlString: String, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(.failure(YandexError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(YandexError.transport(error)))
                return
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                completion(.failure(YandexError.http(http.statusCode)))
                return
            }
            guard let data = data else {
                completion(.failure(YandexError.noData))
                return
            }
            completion(.success(data))
        }.resume()
    }

    // MARK: - Private

    private func request<T: Decodable>(
        path: String,
        query: [String: String],
        token: String,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        var components = URLComponents(url: baseURL.appendingPathComponent(path),
                                       resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else {
            completion(.failure(YandexError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("OAuth \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    completion(.failure(YandexError.transport(error)))
                    return
                }
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    completion(.failure(YandexError.http(http.statusCode)))
                    return
                }
                guard let data = data else {
                    completion(.failure(YandexError.noData))
                    return
                }
                do {
                    let decoded = try self.decoder.decode(T.self, from: data)
                    completion(.success(decoded))
                } catch {
                    completion(.failure(YandexError.transport(error)))
                }
            }
        }.resume()
    }
}