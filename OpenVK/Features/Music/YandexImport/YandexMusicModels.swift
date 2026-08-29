//
//  YandexMusicModels.swift
//  OpenVK for iOS
//
//  Модели данных API Яндекс Музыки (api.music.yandex.net).
//  Имена полей совпадают с JSON-ключами (camelCase), поэтому
//  стандартный JSONDecoder без стратегии ключей подходит напрямую.
//

import Foundation

// MARK: - Константы

enum YandexConstants {
    /// Публичный OAuth client_id, используемый мобильным приложением Яндекс Музыки
    /// в открытых проектах. Позволяет получить токен через oauth.yandex.ru.
    static let clientID = "23cabbbdc6cd41889bfd28c17d1fd20c"
    static let oauthAuthorizeURL =
        "https://oauth.yandex.ru/authorize?response_type=token&client_id=\(clientID)"
    static let tokenKey = "yandex.music.token"
    static let lastLoginKey = "yandex.music.last_login"
}

// MARK: - Аккаунт

struct YandexAccountStatusResult: Decodable {
    let account: YandexAccount?
}

struct YandexAccount: Decodable {
    let uid: Int?
    let login: String?
}

// MARK: - Треки

struct YandexArtist: Decodable, Hashable {
    let name: String?
}

struct YandexAlbum: Decodable, Hashable {
    let coverUri: String?
}

struct YandexTrack: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String?
    let artists: [YandexArtist]?
    let albums: [YandexAlbum]?
    let durationMs: Int?

    var artistName: String {
        artists?.compactMap { $0.name }.joined(separator: ", ") ?? "Исполнитель"
    }

    var durationText: String {
        guard let ms = durationMs, ms > 0 else { return "--:--" }
        let seconds = ms / 1000
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    var coverURLString: String? {
        guard let uri = albums?.first?.coverUri else { return nil }
        return "https://" + uri.replacingOccurrences(of: "%%", with: "400x400")
    }
}

struct YandexPlaylistResponse: Decodable {
    let result: YandexPlaylist?
}

struct YandexPlaylist: Decodable {
    let tracks: [YandexTrack]?
}

// MARK: - Ссылка на скачивание

struct YandexDownloadInfoResponse: Decodable {
    let result: [YandexDownloadInfo]?
}

struct YandexDownloadInfo: Decodable {
    let codec: String?
    let bitrateInKbps: Int?
    let directLink: String?
}

// MARK: - Ошибки

enum YandexError: LocalizedError {
    case invalidURL
    case noData
    case noAccount
    case noToken
    case http(Int)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Некорректная ссылка"
        case .noData:
            return "Не удалось получить данные от Яндекс Музыки"
        case .noAccount:
            return "Не удалось определить аккаунт Яндекс Музыки"
        case .noToken:
            return "Не удалось получить токен Яндекс Музыки. Проверьте, что вы вошли в аккаунт."
        case .http(let code):
            return "Ошибка Яндекс Музыки (HTTP \(code))"
        case .transport(let error):
            return "Ошибка сети: \(error.localizedDescription)"
        }
    }
}