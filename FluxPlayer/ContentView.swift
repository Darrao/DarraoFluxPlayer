import SwiftUI
import AVKit

struct ContentView: View {
    // ----------------------------------------------------
    // MARK: - Variables d'états (State)
    // ----------------------------------------------------

    // URL saisie par l'utilisateur
    @State private var streamURLString: String = ""

    // États gérant la navigation et le lecteur
    @State private var isPlaying: Bool = false
    @State private var isFullScreen: Bool = false
    @StateObject private var playerViewModel = PlayerViewModel()

    // États pour les notifications d'erreurs
    @State private var showingError: Bool = false
    @State private var errorMessage: String = ""

    // État pour afficher le navigateur IPTV
    @State private var showingIPTVBrowser: Bool = false

    // États pour ajouter manuellement un favori
    @State private var showingAddFavoritePrompt: Bool = false
    @State private var customFavoriteName: String = ""
    @State private var editingExistingFavorite: IPTVChannel? = nil

    @ObservedObject private var favoritesManager = FavoritesManager.shared

    // Historique des flux sauvegardé dans le système (persistant)
    @AppStorage("recentStreams") private var recentStreamsData: String = "[]"

    private var recentStreams: [String] {
        get {
            guard let data = recentStreamsData.data(using: .utf8),
                  let urls = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return urls
        }
        nonmutating set {
            if let data = try? JSONEncoder().encode(newValue),
               let string = String(data: data, encoding: .utf8) {
                recentStreamsData = string
            }
        }
    }

    // ----------------------------------------------------
    // MARK: - Vue Principale
    // ----------------------------------------------------
    var body: some View {
        NavigationStack {
            ZStack {
                // Fond dégradé global
                FPTheme.backgroundGradient
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 28) {

                        // ── Lecteur inline ──────────────────
                        if isPlaying, let currentPlayer = playerViewModel.player {
                            InlineVideoPlayerView(
                                player: currentPlayer,
                                viewModel: playerViewModel,
                                onRefresh: { reloadStream() },
                                onFullscreen: {
                                    #if os(macOS)
                                    if let window = NSApplication.shared.windows.first {
                                        window.toggleFullScreen(nil)
                                    }
                                    #else
                                    isFullScreen = true
                                    #endif
                                },
                                onClose: { stopPlaying() },
                                isFavorite: favoritesManager.isFavorite(IPTVChannel(name: "", group: "", logoURL: nil, streamURL: playerViewModel.currentURL ?? URL(string: "about:blank")!)),
                                onFavorite: {
                                    if let currentURL = playerViewModel.currentURL {
                                        let dummy = IPTVChannel(name: "", group: "", logoURL: nil, streamURL: currentURL)
                                        if let existing = favoritesManager.favorites.first(where: { $0.streamURL == currentURL }) {
                                            editingExistingFavorite = existing
                                            customFavoriteName = existing.name
                                        } else {
                                            editingExistingFavorite = nil
                                            customFavoriteName = ""
                                        }
                                        showingAddFavoritePrompt = true
                                    }
                                }
                            )
                            .aspectRatio(16/9, contentMode: .fit)
                            .frame(maxWidth: 900)
                            .clipShape(RoundedRectangle(cornerRadius: FPTheme.cornerRadius, style: .continuous))
                            .shadow(color: FPTheme.accentBlue.opacity(0.15), radius: 30, y: 10)
                            .padding(.horizontal)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            #if os(tvOS)
                            .focusSection()
                            #endif
                        }

                        // ── Contenu du Dashboard ────────────────
                        #if os(tvOS)
                        HStack(alignment: .top, spacing: 60) {
                            // Colonne GAUCHE : Favoris
                            VStack(alignment: .leading, spacing: 20) {
                                if !favoritesManager.favorites.isEmpty {
                                    favoritesSection
                                        .focusSection()
                                } else {
                                    VStack(alignment: .leading, spacing: 14) {
                                        SectionHeader(title: "Favoris", icon: "star.fill")
                                        Text("Aucun favori")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 20)
                                }
                                Spacer()
                            }
                            .frame(width: 300)

                            // Colonne DROITE : Actions et Flux récents
                            VStack(alignment: .leading, spacing: 30) {
                                urlInputSection
                                    .focusSection()

                                if !isPlaying {
                                    actionButtons
                                        .focusSection()
                                }

                                if !recentStreams.isEmpty {
                                    recentStreamsSection
                                        .focusSection()
                                }
                                Spacer()
                            }
                        }
                        .padding(.horizontal, 40)
                        #else
                        // Layout vertical standard (iOS/macOS)
                        VStack(spacing: 28) {
                            urlInputSection

                            if !isPlaying {
                                actionButtons
                                    .transition(.opacity)
                            }

                            if !favoritesManager.favorites.isEmpty {
                                favoritesSection
                            }

                            if !recentStreams.isEmpty {
                                recentStreamsSection
                            }
                        }
                        #endif

                        Spacer(minLength: 40)
                    }
                    .padding(.vertical, 20)
                }
            }
            // Full-screen cover (tvOS / iOS)
            .tvOSFullScreenCover(isPresented: $isFullScreen) {
                VideoPlayerWrapper(player: playerViewModel.player, viewModel: playerViewModel)
            }
            #if os(tvOS)
            .fullScreenCover(isPresented: $showingIPTVBrowser) {
                IPTVPlaylistSelectionView { streamURL in
                    self.showingIPTVBrowser = false
                    self.streamURLString = streamURL
                    self.startPlaying(urlString: streamURL)
                }
            }
            #else
            .sheet(isPresented: $showingIPTVBrowser) {
                IPTVPlaylistSelectionView { streamURL in
                    self.showingIPTVBrowser = false
                    self.streamURLString = streamURL
                    self.startPlaying(urlString: streamURL)
                }
            }
            #endif
            .alert("Erreur", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .onChange(of: playerViewModel.errorMessage) { newValue in
                if let err = newValue {
                    self.showError(err)
                }
            }
            .alert(editingExistingFavorite == nil ? "Ajouter aux favoris" : "Renommer le favori", isPresented: $showingAddFavoritePrompt) {
                TextField("Nom (ex: TF1)", text: $customFavoriteName)
                
                if let existing = editingExistingFavorite {
                    Button("Enregistrer") {
                        let newName = customFavoriteName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let finalName = newName.isEmpty ? "Flux personnalisé" : newName
                        favoritesManager.renameFavorite(with: existing.streamURL, newName: finalName)
                    }
                    Button("Retirer des favoris", role: .destructive) {
                        favoritesManager.removeFavorite(with: existing.streamURL)
                    }
                } else {
                    Button("Ajouter") {
                        let cleanURL = streamURLString.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let url = URL(string: cleanURL) {
                            let newName = customFavoriteName.trimmingCharacters(in: .whitespacesAndNewlines)
                            let finalName = newName.isEmpty ? "Flux personnalisé" : newName
                            
                            let newChannel = IPTVChannel(
                                name: finalName,
                                group: "Personnalisé",
                                logoURL: nil,
                                streamURL: url
                            )
                            if !favoritesManager.isFavorite(newChannel) {
                                favoritesManager.favorites.append(newChannel)
                            }
                        }
                    }
                }
                
                Button("Annuler", role: .cancel) { }
            } message: {
                if editingExistingFavorite == nil {
                    Text("Entrez le nom pour enregistrer ce flux dans vos favoris.")
                } else {
                    Text("Modifiez le nom de ce favori ou retirez-le.")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 700, minHeight: 650)
        #endif
    }

    // =========================================================================
    // MARK: - Sous-vues de la page principale
    // =========================================================================


    /// Champ de saisie d'URL avec style glassmorphique.
    private var urlInputSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "link")
                .foregroundColor(FPTheme.subtleWhite)
                .font(.system(size: 16, weight: .medium))

            TextField("Entrez l'URL du flux (http/https)", text: $streamURLString)
                .textFieldStyle(.plain)
                .foregroundColor(.white)
                #if os(iOS)
                .keyboardType(.URL)
                .autocapitalization(.none)
                #endif

            if !streamURLString.isEmpty {
                Button(action: { streamURLString = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(FPTheme.subtleWhite)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassBackground(radius: 14)
        .frame(maxWidth: 700)
        .padding(.horizontal, 20)
    }

    /// Boutons principaux (Lire, Parcourir IPTV).
    private var actionButtons: some View {
        VStack(spacing: 14) {
            // Bouton Lire
            Button(action: { startPlaying(urlString: streamURLString) }) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text("Lire la vidéo")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: 320)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [FPTheme.accentBlue, FPTheme.accentBlue.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .shadow(color: FPTheme.accentBlue.opacity(0.4), radius: 12, y: 4)
            }
            #if os(tvOS)
            .buttonStyle(.card)
            #else
            .buttonStyle(.plain)
            #endif

            // Bouton Favoris (Manuel)
            if !streamURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: {
                    customFavoriteName = ""
                    editingExistingFavorite = nil
                    showingAddFavoritePrompt = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("Ajouter aux favoris")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: 320)
                    .padding(.vertical, 12)
                    .background(
                        Capsule().fill(Color.white.opacity(0.1))
                            .overlay(Capsule().stroke(FPTheme.accentBlue.opacity(0.5), lineWidth: 1))
                    )
                }
                #if os(tvOS)
                .buttonStyle(.card)
                #else
                .buttonStyle(.plain)
                #endif
            }

            // Bouton IPTV
            Button(action: { showingIPTVBrowser = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .font(.system(size: 16, weight: .medium))
                    Text("Parcourir les chaînes IPTV")
                        .font(.system(size: 15, weight: .medium))
                }
                .foregroundColor(.white)
                .frame(maxWidth: 320)
                .padding(.vertical, 12)
                .background(
                    Capsule().fill(Color.white.opacity(0.1))
                        .overlay(Capsule().stroke(FPTheme.cardBorder, lineWidth: 0.5))
                )
            }
            #if os(tvOS)
            .buttonStyle(.card)
            #else
            .buttonStyle(.plain)
            #endif
        }
    }

    /// Section Favoris avec défilement horizontal de cartes.
    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Favoris", icon: "star.fill")
                .padding(.horizontal, 20)

            #if os(tvOS)
            // Sur tvOS, on liste les favoris verticalement dans la colonne de gauche
            VStack(spacing: 14) {
                ForEach(favoritesManager.favorites) { channel in
                    FavoriteChannelCard(channel: channel) {
                        streamURLString = channel.streamURL.absoluteString
                        startPlaying(urlString: channel.streamURL.absoluteString)
                    }
                    .contextMenu {
                        Button(action: { favoritesManager.toggleFavorite(channel) }) {
                            Label("Retirer des favoris", systemImage: "star.slash")
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            #else
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(favoritesManager.favorites) { channel in
                        FavoriteChannelCard(channel: channel) {
                            streamURLString = channel.streamURL.absoluteString
                            startPlaying(urlString: channel.streamURL.absoluteString)
                        }
                        .contextMenu {
                            Button(action: { favoritesManager.toggleFavorite(channel) }) {
                                Label("Retirer des favoris", systemImage: "star.slash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            #endif
        }
    }

    /// Section Flux Récents.
    private var recentStreamsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Flux récents", icon: "clock.arrow.circlepath")
                .padding(.horizontal, 20)

            VStack(spacing: 8) {
                ForEach(Array(recentStreams.enumerated()), id: \.element) { index, url in
                    Button(action: {
                        streamURLString = url
                        startPlaying(urlString: url)
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(FPTheme.accentBlue.opacity(0.8))

                            Text(url)
                                .font(.system(size: 13, weight: .regular, design: .monospaced))
                                .foregroundColor(FPTheme.subtleWhite)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            #if !os(tvOS)
                            Button(action: { deleteRecentStream(at: IndexSet(integer: index)) }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(FPTheme.subtleWhite)
                                    .frame(width: 26, height: 26)
                                    .background(Circle().fill(Color.white.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                            #endif
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .glassBackground(radius: 12)
                    }
                    #if os(tvOS)
                    .buttonStyle(.card)
                    #else
                    .buttonStyle(.plain)
                    #endif
                }
            }
            .frame(maxWidth: 700)
            .padding(.horizontal, 20)
        }
    }

    // ----------------------------------------------------
    // MARK: - Fonctions Logiques
    // ----------------------------------------------------

    private func startPlaying(urlString: String) {
        let cleanURLString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = URL(string: cleanURLString),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()) else {
            showError("L'URL saisie est invalide. Vérifiez qu'elle commence bien par http:// ou https://.")
            return
        }

        addRecentStream(url: cleanURLString)
        playerViewModel.startPlaying(url: url)

        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            self.isPlaying = true
        }
    }

    private func stopPlaying() {
        playerViewModel.stop()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            isPlaying = false
        }
    }

    private func reloadStream() {
        guard let urlString = streamURLString.isEmpty == false ? streamURLString : nil else { return }
        playerViewModel.stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            startPlaying(urlString: urlString)
        }
    }

    private func showError(_ message: String) {
        self.errorMessage = message
        self.showingError = true
    }

    private func addRecentStream(url: String) {
        var streams = recentStreams
        if let index = streams.firstIndex(of: url) {
            streams.remove(at: index)
        }
        streams.insert(url, at: 0)
        if streams.count > 10 {
            streams = Array(streams.prefix(10))
        }
        recentStreams = streams
    }

    private func deleteRecentStream(at offsets: IndexSet) {
        var streams = recentStreams
        streams.remove(atOffsets: offsets)
        recentStreams = streams
    }
}

// =============================================================================
// MARK: - Carte de chaîne favorite
// =============================================================================

struct FavoriteChannelCard: View {
    let channel: IPTVChannel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                // Logo
                Group {
                    if let logoURL = channel.logoURL {
                        AsyncImage(url: logoURL) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .scaledToFit()
                            } else {
                                tvPlaceholder
                            }
                        }
                    } else {
                        tvPlaceholder
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Nom
                Text(channel.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                // Groupe
                Text(channel.group)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(FPTheme.subtleWhite)
                    .lineLimit(1)
            }
            .frame(width: 110)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .glassBackground(radius: 14)
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.plain)
        #endif
    }

    private var tvPlaceholder: some View {
        Image(systemName: "tv")
            .font(.system(size: 24))
            .foregroundColor(FPTheme.subtleWhite)
            .frame(width: 56, height: 56)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// =============================================================================
// MARK: - Sous-Vues (Inline et Fullscreen)
// =============================================================================

struct InlineVideoPlayerView: View {
    let player: AVPlayer
    @ObservedObject var viewModel: PlayerViewModel
    let onRefresh: () -> Void
    let onFullscreen: (() -> Void)?
    let onClose: () -> Void
    let isFavorite: Bool
    let onFavorite: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                // Lecteur vidéo
                #if os(macOS)
                MacVideoPlayerView(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: FPTheme.cornerRadius, style: .continuous))
                #else
                VideoPlayer(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: FPTheme.cornerRadius, style: .continuous))
                    #if os(tvOS)
                    .focusable(false)
                    #endif
                #endif

                // Overlay de contrôles (auto-hide sur tvOS uniquement si plein écran)
                AdvancedPlayerControlsView(viewModel: viewModel, isFullScreen: false)

                // Boutons flottants (plein écran / fermer)
                VStack {
                    HStack {
                        // Bouton Fermer (en haut à gauche)
                        floatingButton(icon: "xmark", action: onClose)

                        Spacer()

                        // Bouton Plein Écran (en haut à droite)
                        if let onFullscreen = onFullscreen {
                            floatingButton(icon: "arrow.up.left.and.arrow.down.right", action: onFullscreen)
                        }
                    }
                    .padding(12)
                    Spacer()
                }
            }

            // Barre d'outils sous la vidéo (fiable pour le focus tvOS)
            HStack(spacing: 14) {
                Spacer()
                toolbarButton(icon: isFavorite ? "star.fill" : "star", label: isFavorite ? "Favori" : "Favori", action: onFavorite)
                toolbarButton(icon: "arrow.clockwise", label: "Recharger", action: onRefresh)
                toolbarButton(icon: "xmark", label: "Fermer", action: onClose)
                Spacer()
            }
            #if os(tvOS)
            .buttonStyle(.bordered)
            #elseif os(iOS)
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            #else
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 4)
            #endif
        }
        #if os(tvOS)
        .focusSection()
        #endif
    }

    /// Bouton flottant sur la vidéo (cercle semi-transparent).
    private func floatingButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44) // Légèrement plus grand pour tvOS focus
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                )
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.plain)
        #endif
    }

    /// Bouton texte sous le lecteur.
    private func toolbarButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .help(label)
    }
}


#if os(macOS)
struct MacVideoPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.allowsPictureInPicturePlayback = true
        view.showsFullScreenToggleButton = true
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}
#endif

// Vue utilisée lors du passage en fullScreenCover (tvOS ou iOS si existant)
struct VideoPlayerWrapper: View {
    let player: AVPlayer?
    @ObservedObject var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let p = player {
                ZStack {
                    // Fond noir pour éviter les flashs
                    Color.black.ignoresSafeArea()

                    // Lecteur plein écran
                    #if os(macOS)
                    MacVideoPlayerView(player: p)
                        .ignoresSafeArea()
                    #else
                    VideoPlayer(player: p)
                        .ignoresSafeArea()
                        #if os(tvOS)
                        .focusable(false)
                        #endif
                    #endif

                    // Overlay de contrôles (avec auto-hide)
                    AdvancedPlayerControlsView(viewModel: viewModel, isFullScreen: true)

                    // Bouton retour
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: { dismiss() }) {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        Circle()
                                            .fill(.ultraThinMaterial)
                                            .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                                    )
                            }
                            #if os(tvOS)
                            .buttonStyle(.card)
                            #else
                            .buttonStyle(.plain)
                            #endif
                            .padding(20)
                        }
                        Spacer()
                    }
                }
                #if os(tvOS)
                .focusSection()
                #endif
                .onDisappear {
                    // Le parent (ContentView) gère la persistance de la lecture
                }
            } else {
                ZStack {
                    Color.black.ignoresSafeArea()
                    ProgressView("Chargement...")
                        .foregroundColor(.white)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}

extension View {
    @ViewBuilder
    func tvOSFullScreenCover<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(tvOS)
        self.fullScreenCover(isPresented: isPresented, onDismiss: onDismiss, content: content)
        #else
        self // Ignore sur macOS 13
        #endif
    }
}
