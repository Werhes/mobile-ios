//
//  MusicView.swift
//  OpenVK for iOS
//
//  Раздел «Музыка». Отправляет запросы к audio.* методам OpenVK API
//  и воспроизводит аудиозаписи через встроенный плеер.
//

import SwiftUI

struct MusicView: View {

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = MusicViewModel()
    @ObservedObject private var player = MusicPlayer.shared
    @ObservedObject private var offlineStore = OfflineTracksStore.shared
    @State private var searchQuery = ""
    @State private var showFullPlayer = false
    @State private var showYandexImport = false

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                content
                    .padding(.bottom, player.hasCurrentTrack ? 96 : 0)

                if player.hasCurrentTrack {
                    MiniPlayerBar(player: player) {
                        showFullPlayer = true
                    }
                    .transition(.move(edge: .bottom))
                }
            }
            .navigationTitle("Музыка")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Назад")
                }
            }
            .searchable(text: $searchQuery, prompt: "Поиск музыки")
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showFullPlayer) {
            Group {
                if #available(iOS 16.0, *) {
                    FullPlayerView(
                        player: player,
                        onLike: { track in viewModel.toggleLike(track) },
                        onDownload: { track in viewModel.download(track) }
                    )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                } else {
                    FullPlayerView(
                        player: player,
                        onLike: { track in viewModel.toggleLike(track) },
                        onDownload: { track in viewModel.download(track) }
                    )
                }
            }
            .accentColor(Color.appAccent)
            .tint(Color.appAccent)
        }
        .sheet(isPresented: $showYandexImport) {
            YandexImportView()
                .accentColor(Color.appAccent)
                .tint(Color.appAccent)
        }
        .onChange(of: searchQuery) { query in
            viewModel.search(query)
        }
        .onChange(of: viewModel.selectedSection) { _ in
            viewModel.load()
        }
        .alert(item: $viewModel.activeAlert) { alert in
            switch alert {
            case .added:
                return Alert(
                    title: Text("Добавлено"),
                    message: Text("Трек добавлен в вашу музыку"),
                    dismissButton: .cancel(Text("OK"))
                )
            case .downloaded:
                return Alert(
                    title: Text("Скачано"),
                    message: Text("Трек сохранён в приложении и доступен офлайн."),
                    dismissButton: .cancel(Text("OK"))
                )
            case .error(let message):
                return Alert(
                    title: Text("Ошибка"),
                    message: Text(message),
                    dismissButton: .cancel(Text("OK"))
                )
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            if searchQuery.isEmpty {
                Picker("Раздел", selection: $viewModel.selectedSection) {
                    ForEach(MusicSection.allCases) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            Button {
                showYandexImport = true
            } label: {
                Label("Перенос из Яндекс Музыки", systemImage: "arrow.triangle.swap")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            if viewModel.isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if let error = viewModel.errorMessage {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text(error)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Button("Повторить") {
                        viewModel.load()
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
            } else if viewModel.tracks.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Треки не найдены")
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.tracks) { track in
                            trackRow(track)
                            SectionSeparator()
                        }
                    }
                }
            }
        }
        .onAppear {
            if viewModel.tracks.isEmpty && !viewModel.isLoading {
                viewModel.load()
            }
        }
        .refreshable {
            viewModel.load()
        }
    }

    private func trackRow(_ track: AudioTrack) -> some View {
        HStack(spacing: 12) {
            Button(action: {
                HapticManager.impact(.light)
                if isCurrent(track) {
                    player.togglePlayPause()
                } else {
                    player.play(track: track, in: viewModel.tracks)
                }
            }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(track.color)
                    if isCurrent(track) && (player.isLoading || player.isPlaying) {
                        if player.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        }
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .offset(x: 1)
                    }
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(PlainButtonStyle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    // Индикатор «сейчас играет» — сохраняется при возврате в раздел
                    if isCurrent(track) && player.isPlaying {
                        Image(systemName: "waveform")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.appAccent)
                    }
                    Text(track.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isCurrent(track) ? .appAccent : .primary)
                        .lineLimit(1)
                }
                Text(track.artist)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 6) {
                // Индикатор лайка
                if offlineStore.isLiked(track) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.appAccent)
                }
                Text(track.duration)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                if offlineStore.isDownloaded(track) {
                    viewModel.removeDownload(track)
                } else {
                    viewModel.download(track)
                }
            } label: {
                Label(
                    offlineStore.isDownloaded(track) ? "Удалить из скачанного" : "Скачать",
                    systemImage: offlineStore.isDownloaded(track) ? "trash" : "arrow.down.circle"
                )
            }

            Button {
                viewModel.toggleLike(track)
            } label: {
                Label(
                    offlineStore.isLiked(track) ? "Убрать из моих" : "Добавить к себе",
                    systemImage: offlineStore.isLiked(track) ? "heart.slash" : "plus.circle"
                )
            }
        }
    }

    /// Сравнение текущего трека по стабильной идентичности (vkID+ownerID),
    /// чтобы индикатор «сейчас играет» сохранялся при возврате в раздел и смене вкладки.
    private func isCurrent(_ track: AudioTrack) -> Bool {
        guard let current = player.currentTrack else { return false }
        if let trackID = track.vkID, let currentID = current.vkID,
           let trackOwner = track.ownerID, let currentOwner = current.ownerID {
            return trackID == currentID && trackOwner == currentOwner
        }
        return track.title == current.title && track.artist == current.artist
    }
}

// MARK: - Мини-плеер

private struct MiniPlayerBar: View {
    @ObservedObject var player: MusicPlayer
    var onTap: () -> Void

    @State private var isEditingScrub = false
    @State private var scrubValue = 0.0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onTap) {
                    HStack(spacing: 10) {
                        Group {
                            if let currentTrack = player.currentTrack {
                                AsyncArtworkView(track: currentTrack)
                            } else {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.secondary.opacity(0.2))
                                    Image(systemName: "music.note")
                                        .font(.system(size: 16))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.currentTrack?.title ?? "")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Text(player.currentTrack?.artist ?? "")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())

                Spacer(minLength: 4)

                transportButtons

                shuffleRepeatButtons

                Button(action: onTap) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            HStack(spacing: 8) {
                Text(formatTime(player.currentTime))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(.secondary)
                Slider(
                    value: scrubBinding,
                    in: 0...max(player.duration, 0.1),
                    onEditingChanged: { editing in
                        if editing {
                            isEditingScrub = true
                            scrubValue = player.currentTime
                        } else {
                            isEditingScrub = false
                            player.seek(to: scrubValue)
                        }
                    }
                )
                .controlSize(.small)
                .tint(Color.appAccent)
                Text(formatTime(player.duration))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color.white)
        .overlay(alignment: .top) {
            Divider()
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: Color.black.opacity(0.12), radius: 8, y: 2)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private var transportButtons: some View {
        HStack(spacing: 12) {
            Button {
                player.playPrevious()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
            }
            .buttonStyle(PlainButtonStyle())

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isLoading ? "ellipsis"
                    : (player.isPlaying ? "pause.circle.fill" : "play.circle.fill"))
                    .font(.system(size: 30))
                    .foregroundColor(.primary)
            }
            .buttonStyle(PlainButtonStyle())

            Button {
                player.playNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private var shuffleRepeatButtons: some View {
        HStack(spacing: 12) {
            Button {
                player.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 13))
                    .foregroundColor(player.shuffleEnabled ? .appAccent : .secondary)
            }
            .buttonStyle(PlainButtonStyle())

            Button {
                player.cycleRepeatMode()
            } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.system(size: 13))
                    .foregroundColor(player.repeatMode == .off ? .secondary : .appAccent)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private var scrubBinding: Binding<Double> {
        Binding(
            get: { isEditingScrub ? scrubValue : player.currentTime },
            set: { scrubValue = $0 }
        )
    }

    private func formatTime(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.isFinite ? seconds : 0))
        let m = s / 60
        let sec = s % 60
        return String(format: "%d:%02d", m, sec)
    }
}

// MARK: - Полноэкранный плеер

private struct FullPlayerView: View {
    @ObservedObject var player: MusicPlayer
    @ObservedObject var offlineStore = OfflineTracksStore.shared
    let onLike: (AudioTrack) -> Void
    let onDownload: (AudioTrack) -> Void

    @Environment(\.dismiss) private var dismiss

    private var track: AudioTrack? { player.currentTrack }
    private var accent: Color { track?.color ?? .appAccent }

    private func isLiked(_ track: AudioTrack) -> Bool {
        offlineStore.isLiked(track)
    }

    var body: some View {
        ZStack {
            playerBackground

            if let track = track {
                VStack(spacing: 0) {
                    header(track)

                    Spacer(minLength: 28)

                    artwork(track)

                    Spacer(minLength: 30)

                    metadata(track)

                    Spacer(minLength: 26)

                    progressControls

                    Spacer(minLength: 20)

                    primaryControls

                    Spacer(minLength: 22)

                    quickActions(track)

                    Spacer(minLength: 16)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            } else {
                ProgressView()
            }
        }
        .foregroundStyle(Color.primary)
    }

    // MARK: - Фон (размытая обложка + градиент)

    private var playerBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    accent.opacity(0.55),
                    accent.opacity(0.28),
                    accent.opacity(0.12),
                    Color(.systemBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            GeometryReader { geo in
                Circle()
                    .fill(accent.opacity(0.35))
                    .frame(width: geo.size.width * 1.4, height: geo.size.width * 1.4)
                    .blur(radius: 90)
                    .offset(y: -geo.size.height * 0.25)
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }

    // MARK: - Шапка

    private func header(_ track: AudioTrack) -> some View {
        ZStack {
            Text("СЕЙЧАС ИГРАЕТ")
                .font(.caption2.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(.secondary)

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                Menu {
                    Button {
                        onDownload(track)
                    } label: {
                        Label("Скачать", systemImage: "arrow.down.circle")
                    }
                    Button {
                        onLike(track)
                    } label: {
                        Label(
                            isLiked(track) ? "Убрать из моих" : "Добавить к себе",
                            systemImage: isLiked(track) ? "heart.slash" : "plus.circle"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Обложка

    private func artwork(_ track: AudioTrack) -> some View {
        AsyncArtworkView(track: track)
            .frame(width: 290, height: 290)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(0.35), radius: 26, y: 14)
    }

    // MARK: - Метаданные

    private func metadata(_ track: AudioTrack) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(track.title)
                    .font(.system(size: 22, weight: .bold))
                    .lineLimit(2)
                Text(track.artist)
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            Button {
                onLike(track)
            } label: {
                Image(systemName: isLiked(track) ? "heart.fill" : "heart")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(isLiked(track) ? Color.red : Color.secondary)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Прогресс

    private var progressControls: some View {
        VStack(spacing: 3) {
            Slider(
                value: Binding(
                    get: { player.currentTime },
                    set: { value in
                        player.currentTime = value
                        player.seek(to: value)
                    }
                ),
                in: 0...max(1, player.duration)
            )
            .disabled(player.duration == 0)
            .tint(Color.primary)

            HStack {
                Text(formatTime(player.currentTime))
                Spacer()
                Text("-\(formatTime(max(player.duration - player.currentTime, 0)))")
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Основные кнопки

    private var primaryControls: some View {
        HStack(spacing: 0) {
            shuffleButton
            Spacer()
            transportButton("backward.fill", label: "Предыдущий трек") {
                player.playPrevious()
            }
            Spacer()
            playPauseButton
            Spacer()
            transportButton("forward.fill", label: "Следующий трек") {
                player.playNext()
            }
            Spacer()
            repeatButton
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(.regularMaterial, in: Capsule())
    }

    private var playPauseButton: some View {
        Button {
            player.togglePlayPause()
        } label: {
            ZStack {
                Circle().fill(Color.primary)
                if player.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(.systemBackground)))
                } else {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 29, weight: .bold))
                        .foregroundColor(Color(.systemBackground))
                        .offset(x: player.isPlaying ? 0 : 2)
                }
            }
            .frame(width: 64, height: 64)
            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
    }

    private func transportButton(_ image: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.system(size: 25, weight: .semibold))
                .frame(width: 48, height: 52)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var shuffleButton: some View {
        Button {
            player.toggleShuffle()
        } label: {
            Image(systemName: "shuffle")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(player.shuffleEnabled ? Color.primary : Color.secondary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Перемешать")
    }

    private var repeatButton: some View {
        Button {
            player.cycleRepeatMode()
        } label: {
            Image(systemName: repeatIcon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(player.repeatMode != .off ? Color.primary : Color.secondary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Повтор")
    }

    private var repeatIcon: String {
        switch player.repeatMode {
        case .off, .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    // MARK: - Быстрые действия

    private func quickActions(_ track: AudioTrack) -> some View {
        HStack(spacing: 0) {
            quickAction("arrow.down.circle", title: "Скачать") {
                onDownload(track)
            }
            quickAction(
                isLiked(track) ? "heart.slash" : "heart",
                title: isLiked(track) ? "Убрать из моих" : "В медиатеку"
            ) {
                onLike(track)
            }
        }
    }

    private func quickAction(_ image: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: image)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN, seconds.isFinite else { return "00:00" }
        let sec = Int(seconds) % 60
        let min = (Int(seconds) / 60) % 60
        let hr = Int(seconds) / 3600
        if hr > 0 {
            return String(format: "%d:%02d:%02d", hr, min, sec)
        }
        return String(format: "%02d:%02d", min, sec)
    }
}

// MARK: - Обложка (iTunes API)

private struct AsyncArtworkView: View {
    @ObservedObject private var loader = ITunesArtworkLoader.shared
    let track: AudioTrack

    var body: some View {
        Group {
            if let url = loader.artworkURL(for: track) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure, .empty:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .onAppear { loader.load(track) }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [track.color, track.color.opacity(0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: 60, weight: .semibold))
                .foregroundColor(.white.opacity(0.92))
        }
    }
}