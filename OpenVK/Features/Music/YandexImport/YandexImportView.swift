//
//  YandexImportView.swift
//  OpenVK for iOS
//
//  Экран переноса музыки из Яндекс Музыки в OpenVK:
//  1. Вход через WebView (автоматически ловится токен)
//  2. Выбор треков из Яндекс Музыки ("Мне нравится")
//  3. «Далее» → скачивание и загрузка каждого трека в OpenVK
//

import SwiftUI

struct YandexImportView: View {

    private enum Phase {
        case auth          // показываем WebView для входа
        case loading       // получаем аккаунт и список треков
        case selection     // выбор треков
        case transferring  // идёт перенос
        case done(imported: Int, skipped: Int, failed: Int)
    }

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .auth
    @State private var tracks: [YandexTrack] = []
    @State private var selectedIDs: Set<Int> = []
    @State private var errorMessage: ImportError?

    // Progress
    @State private var totalToTransfer = 0
    @State private var completed = 0
    @State private var currentTrackTitle = ""

    private let service = YandexMusicService.shared
    private let uploader = OpenVKAudioUploader.shared

    var body: some View {
        NavigationView {
            Group {
                switch phase {
                case .auth:
                    authView
                case .loading:
                    loadingView("Загружаем вашу музыку…")
                case .selection:
                    selectionView
                case .transferring:
                    transferringView
                case .done(let imported, let skipped, let failed):
                    doneView(imported: imported, skipped: skipped, failed: failed)
                }
            }
            .navigationTitle("Перенос из Яндекс Музыки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear { startIfLoggedIn() }
        .alert(item: $errorMessage) { error in
            Alert(
                title: Text("Ошибка"),
                message: Text(error.message),
                dismissButton: .cancel(Text("OK"))
            )
        }
    }

    // MARK: - Аутентификация

    private var authView: some View {
        VStack(spacing: 12) {
            YandexMusicAuthView { token in
                handle(token: token)
            }
            .ignoresSafeArea()

            Text("Войдите в аккаунт Яндекс Музыки. Приложение автоматически определит успешный вход.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(12)
        }
    }

    private func startIfLoggedIn() {
        guard case .auth = phase else { return }
        if let token = YandexMusicService.storedToken {
            handle(token: token)
        }
    }

    private func handle(token raw: String) {
        guard let token = YandexMusicService.cleanToken(raw) else {
            errorMessage = ImportError(message: YandexError.noToken.localizedDescription)
            return
        }
        YandexMusicService.storedToken = token
        phase = .loading
        loadTracks(token: token)
    }

    private func loadTracks(token: String) {
        service.fetchUid(token: token) { [self] result in
            switch result {
            case .success(let uid):
                self.fetchLikedTracks(token: token, uid: uid)
            case .failure(let error):
                self.phase = .auth
                self.errorMessage = ImportError(message: error.localizedDescription)
            }
        }
    }

    private func fetchLikedTracks(token: String, uid: Int) {
        service.fetchLikedTracks(token: token, uid: uid) { [self] result in
            switch result {
            case .success(let tracks):
                self.tracks = tracks
                self.selectedIDs = Set(tracks.map { $0.id })
                self.phase = .selection
            case .failure(let error):
                self.phase = .auth
                self.errorMessage = ImportError(message: error.localizedDescription)
            }
        }
    }

    // MARK: - Выбор треков

    private var selectionView: some View {
        VStack(spacing: 0) {
            if tracks.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "heart.slash")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("В плейлисте «Мне нравится» пока нет треков")
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(tracks) { track in
                            trackSelectionRow(track)
                        }
                    }
                }

                Divider()
                Button {
                    beginTransfer()
                } label: {
                    Text("Далее (\(selectedIDs.count))")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedIDs.isEmpty)
                .padding(16)
            }
        }
    }

    private func trackSelectionRow(_ track: YandexTrack) -> some View {
        Button {
            if selectedIDs.contains(track.id) {
                selectedIDs.remove(track.id)
            } else {
                selectedIDs.insert(track.id)
            }
        } label: {
            HStack(spacing: 12) {
                coverThumb(track)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title ?? "Без названия")
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text("\(track.artistName) · \(track.durationText)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: selectedIDs.contains(track.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selectedIDs.contains(track.id) ? .appAccent : Color(.systemGray4))
                    .font(.title3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private func coverThumb(_ track: YandexTrack) -> some View {
        Group {
            if let urlString = track.coverURLString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholderCover
                    }
                }
            } else {
                placeholderCover
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var placeholderCover: some View {
        ZStack {
            Rectangle().fill(Color(.systemGray5))
            Image(systemName: "music.note")
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Перенос

    private func beginTransfer() {
        let selected = tracks.filter { selectedIDs.contains($0.id) }
        totalToTransfer = selected.count
        completed = 0
        phase = .transferring
        transferNext(selected, index: 0, imported: 0, skipped: 0, failed: 0)
    }

    private func transferNext(
        _ items: [YandexTrack],
        index: Int,
        imported: Int,
        skipped: Int,
        failed: Int
    ) {
        guard index < items.count else {
            phase = .done(imported: imported, skipped: skipped, failed: failed)
            return
        }
        let track = items[index]
        currentTrackTitle = track.title ?? "Трек"
        guard let token = YandexMusicService.storedToken else {
            phase = .done(imported: imported, skipped: skipped, failed: failed)
            return
        }

        transfer(track: track, token: token) { result in
            DispatchQueue.main.async { [self] in
                self.completed += 1
                switch result {
                case .success:
                    self.transferNext(items, index: index + 1,
                                      imported: imported + 1, skipped: skipped, failed: failed)
                case .skipped:
                    self.transferNext(items, index: index + 1,
                                      imported: imported, skipped: skipped + 1, failed: failed)
                case .failure:
                    self.transferNext(items, index: index + 1,
                                      imported: imported, skipped: skipped, failed: failed + 1)
                }
            }
        }
    }

    private enum TransferOutcome {
        case success
        case skipped
        case failure
    }

    private func transfer(
        track: YandexTrack,
        token: String,
        completion: @escaping (TransferOutcome) -> Void
    ) {
        service.fetchDownloadURL(token: token, trackId: track.id) { [self] result in
            switch result {
            case .success(let urlString):
                guard let urlString = urlString else {
                    completion(.skipped) // DRM / недоступно
                    return
                }
                self.downloadAndUpload(urlString: urlString, track: track, completion: completion)
            case .failure:
                completion(.failure)
            }
        }
    }

    private func downloadAndUpload(
        urlString: String,
        track: YandexTrack,
        completion: @escaping (TransferOutcome) -> Void
    ) {
        service.downloadTrack(from: urlString) { [self] result in
            switch result {
            case .success(let data):
                let title = track.title ?? "Без названия"
                let artist = track.artistName
                self.uploader.uploadAudio(data: data, title: title, artist: artist) { result in
                    switch result {
                    case .success:
                        completion(.success)
                    case .failure:
                        completion(.failure)
                    }
                }
            case .failure:
                completion(.skipped)
            }
        }
    }

    private var transferringView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.3)
            Text("Переносим «\(currentTrackTitle)»…")
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Text("\(completed) из \(totalToTransfer)")
                .foregroundColor(.secondary)
            if totalToTransfer > 0 {
                ProgressView(value: Double(completed), total: Double(totalToTransfer))
                    .padding(.horizontal, 40)
            }
            Spacer()
        }
    }

    // MARK: - Готово

    private func doneView(imported: Int, skipped: Int, failed: Int) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            Text("Готово")
                .font(.title2.bold())
            VStack(spacing: 6) {
                Label("Перенесено: \(imported)", systemImage: "music.note.list")
                if skipped > 0 {
                    Label("Пропущено (недоступно): \(skipped)", systemImage: "lock")
                        .foregroundColor(.orange)
                }
                if failed > 0 {
                    Label("Ошибок: \(failed)", systemImage: "xmark.circle")
                        .foregroundColor(.red)
                }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            Spacer()
            Button("Готово") { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 24)
        }
    }

    // MARK: - Загрузка

    private func loadingView(_ text: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .scaleEffect(1.3)
            Text(text)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}

// MARK: - Ошибка для alert

private struct ImportError: Identifiable {
    let id = UUID()
    let message: String
}