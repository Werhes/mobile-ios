//
//  OpenVKAudioUploader.swift
//  OpenVK for iOS
//
//  Загрузка аудиофайла в OpenVK (VK-совместимый метод):
//  1. audio.getUploadServer → upload_url
//  2. POST файла (multipart, поле "file") на upload_url → server/audio/hash
//  3. audio.save с этими параметрами и метаданными
//

import Foundation

enum OpenVKAudioUploaderError: LocalizedError {
    case noUploadServer
    case invalidUploadURL
    case badUploadResponse
    case noData
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .noUploadServer:
            return "Не удалось получить адрес загрузки OpenVK"
        case .invalidUploadURL:
            return "Некорректный адрес загрузки OpenVK"
        case .badUploadResponse:
            return "Сервер OpenVK не принял аудиофайл"
        case .noData:
            return "Пустой ответ сервера"
        case .transport(let error):
            return "Ошибка сети: \(error.localizedDescription)"
        }
    }
}

final class OpenVKAudioUploader {

    static let shared = OpenVKAudioUploader()

    private init() {}

    // MARK: - Upload

    /// Полный цикл: получить upload-сервер, отправить MP3, сохранить аудио.
    func uploadAudio(
        data: Data,
        title: String,
        artist: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        getUploadServer { [weak self] result in
            switch result {
            case .success(let uploadURL):
                self?.uploadFile(data: data, to: uploadURL) { result in
                    switch result {
                    case .success(let fields):
                        self?.saveAudio(server: fields["server"],
                                        audio: fields["audio"],
                                        hash: fields["hash"],
                                        title: title,
                                        artist: artist,
                                        completion: completion)
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - audio.getUploadServer

    private struct UploadServerResponse: Decodable {
        let uploadUrl: String?
    }

    private func getUploadServer(completion: @escaping (Result<String, Error>) -> Void) {
        APIClient.shared.call(
            method: "audio.getUploadServer",
            parameters: [:],
            httpMethod: "GET",
            as: UploadServerResponse.self
        ) { (result: Result<UploadServerResponse, APIError>) in
            switch result {
            case .success(let response):
                if let url = response.uploadUrl {
                    completion(.success(url))
                } else {
                    completion(.failure(OpenVKAudioUploaderError.noUploadServer))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Upload file (multipart, поле "file")

    private func uploadFile(
        data: Data,
        to urlString: String,
        completion: @escaping (Result<[String: String], Error>) -> Void
    ) {
        guard let url = URL(string: urlString) else {
            completion(.failure(OpenVKAudioUploaderError.invalidUploadURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("okhttp/4.12.0", forHTTPHeaderField: "User-Agent")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.mp3\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/mpeg\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(OpenVKAudioUploaderError.transport(error)))
                    return
                }
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    completion(.failure(OpenVKAudioUploaderError.badUploadResponse))
                    return
                }
                guard let data = data,
                      let object = try? JSONSerialization.jsonObject(with: data),
                      let json = object as? [String: Any] else {
                    completion(.failure(OpenVKAudioUploaderError.badUploadResponse))
                    return
                }

                var fields: [String: String] = [:]
                for key in ["server", "audio", "hash"] {
                    if let value = json[key] {
                        fields[key] = "\(value)"
                    }
                }
                // OpenVK может вернуть ключи в snake_case
                if let server = json["server"] ?? json["upload_server"] { fields["server"] = "\(server)" }
                completion(.success(fields))
            }
        }.resume()
    }

    // MARK: - audio.save

    private struct SavedAudio: Decodable {}

    private func saveAudio(
        server: String?,
        audio: String?,
        hash: String?,
        title: String,
        artist: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let server = server, let audio = audio, let hash = hash else {
            completion(.failure(OpenVKAudioUploaderError.badUploadResponse))
            return
        }

        var params: [String: String] = [
            "server": server,
            "audio": audio,
            "hash": hash,
            "title": title,
            "artist": artist
        ]
        // У некоторых серверов поле называется audio_id
        if params["audio"] == nil {
            params["audio_id"] = audio
        }

        APIClient.shared.call(
            method: "audio.save",
            parameters: params,
            httpMethod: "GET",
            as: SavedAudio.self
        ) { (result: Result<SavedAudio, APIError>) in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}