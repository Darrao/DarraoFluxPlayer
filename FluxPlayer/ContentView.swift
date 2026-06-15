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
    
    // État pour les toasts de succès
    @State private var toastMessage: String?
    @State private var showingToast: Bool = false

    // Historique des flux sauvegardé dans le système (persistant)
    @AppStorage("recentStreams") private var recentStreamsData: String = "[]"

    private var recentStreams: [RecentStream] {
        get {
            guard let data = recentStreamsData.data(using: .utf8),
                  let items = try? JSONDecoder().decode([RecentStream].self, from: data) else {
                return []
            }
            return items.sorted(by: { $0.date > $1.date })
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
    // ----------------------------------------------------
    // MARK: - Vue Principale (TabView)
    // ----------------------------------------------------
    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                // ONGLET 1 : ACCUEIL
                homeTab
                    .tabItem {
                        Label("Accueil", systemImage: "house.fill")
                    }
                    .tag(0)

                // ONGLET 2 : IPTV
                iptvTab
                    .tabItem {
                        Label("Chaînes", systemImage: "tv.fill")
                    }
                    .tag(1)

                // ONGLET 3 : FAVORIS
                favoritesTab
                    .tabItem {
                        Label("Favoris", systemImage: "star.fill")
                    }
                    .tag(2)
            }
            .accentColor(FPTheme.accentBlue)

            // MINI-PLAYER persistent overlay
            if isPlaying, !isFullScreen {
                miniPlayerOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .fullScreenCover(isPresented: $isFullScreen) {
            VideoPlayerWrapper(player: playerViewModel.player, viewModel: playerViewModel)
        }
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
                    showToast("Favori renommé : \(finalName)")
                }
                Button("Retirer des favoris", role: .destructive) {
                    favoritesManager.removeFavorite(with: existing.streamURL)
                    showToast("Retiré des favoris")
                }
            } else {
                Button("Ajouter") {
                    let cleanURL = streamURLString.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let url = URL(string: cleanURL) {
                        let newName = customFavoriteName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let finalName = newName.isEmpty ? "Flux personnalisé" : newName
                        let newChannel = IPTVChannel(name: finalName, group: "Personnalisé", logoURL: nil, streamURL: url)
                        if !favoritesManager.isFavorite(newChannel) {
                            favoritesManager.favorites.append(newChannel)
                            showToast("Ajouté aux favoris : \(finalName)")
                        }
                    }
                }
            }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text(editingExistingFavorite == nil ? "Entrez le nom pour enregistrer ce flux." : "Modifiez le nom ou retirez-le.")
        }
        .overlay(alignment: .top) {
            if showingToast, let message = toastMessage {
                toastView(message: message)
            }
        }
        #if os(macOS)
        .frame(minWidth: 800, minHeight: 650)
        #endif
    }

    // ----------------------------------------------------
    // MARK: - États Additionnels
    // ----------------------------------------------------
    @State private var selectedTab: Int = 0

    // ----------------------------------------------------
    // MARK: - Onglets
    // ----------------------------------------------------

    private var homeTab: some View {
        NavigationStack {
            ZStack {
                FPTheme.backgroundGradient.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        headerSection
                        
                        // Section Saisie URL (Glassmorphic compact)
                        urlInputSection
                        
                        // Boutons d'action (Lire, Favoris)
                        actionButtons
                            .frame(maxWidth: .infinity)

                        // Section Favoris Rapides (Carousel)
                        if !favoritesManager.favorites.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                SectionHeader(title: "Vos Favoris", icon: "star.fill", subtitle: "Accès rapide à vos chaînes préférées")
                                    .padding(.horizontal, 20)
                                favoritesCarousel
                            }
                        }

                        // Section Flux Récents
                        if !recentStreams.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                SectionHeader(title: "Récemment lus", icon: "clock.arrow.circlepath", subtitle: "Reprenez là où vous vous êtes arrêté")
                                    .padding(.horizontal, 20)
                                recentStreamsList
                            }
                        }
                        
                        Spacer(minLength: 120) // Pour le mini-player
                    }
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("FluxPlayer")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    private var iptvTab: some View {
        IPTVPlaylistSelectionView { channel in
            self.startPlaying(channel: channel)
        }
    }

    private var favoritesTab: some View {
        NavigationStack {
            ZStack {
                FPTheme.backgroundGradient.ignoresSafeArea()
                
                if favoritesManager.favorites.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "star.slash")
                            .font(.system(size: 60))
                            .foregroundColor(FPTheme.subtleWhite)
                        Text("Aucun favori pour le moment")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("Ajoutez des flux manuellement ou parcourez les chaînes IPTV pour les voir ici.")
                            .font(.subheadline)
                            .foregroundColor(FPTheme.subtleWhite)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                            ForEach(favoritesManager.favorites) { channel in
                                FavoriteChannelCard(channel: channel) {
                                    startPlaying(channel: channel)
                                }
                                .contextMenu {
                                    Button(role: .destructive) { favoritesManager.removeFavorite(with: channel.streamURL) } label: {
                                        Label("Retirer", systemImage: "star.slash")
                                    }
                                }
                            }
                        }
                        .padding(20)
                        Spacer(minLength: 100)
                    }
                }
            }
            .navigationTitle("Mes Favoris")
        }
    }

    // ----------------------------------------------------
    // MARK: - Sous-sections Dashboard
    // ----------------------------------------------------

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bienvenue sur")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(FPTheme.subtleWhite)
                Text("FluxPlayer Premium")
                    .font(.system(size: 24, weight: .black))
                    .foregroundColor(.white)
            }
            Spacer()
            // Placeholder User Profile
            ZStack {
                Circle().fill(FPTheme.accentBlue.opacity(0.1)).frame(width: 44, height: 44)
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(FPTheme.accentBlue)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private var favoritesCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(favoritesManager.favorites) { channel in
                    FavoriteChannelCard(channel: channel) {
                        startPlaying(channel: channel)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
    }

    private var recentStreamsList: some View {
        VStack(spacing: 12) {
            ForEach(recentStreams.prefix(5)) { item in
                Button(action: { startPlaying(urlString: item.url) }) {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10).fill(FPTheme.accentBlue.opacity(0.2)).frame(width: 48, height: 48)
                            Image(systemName: "play.fill").foregroundColor(FPTheme.accentBlue)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name).font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                            Text(item.url).font(.system(size: 12)).foregroundColor(FPTheme.subtleWhite).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundColor(FPTheme.subtleWhite)
                    }
                    .padding(12)
                    .glassBackground(radius: 14)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }

    private var miniPlayerOverlay: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                if let player = playerViewModel.player {
                    ZStack {
                        VideoPlayer(player: player)
                            .frame(width: 100, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            // AVKit (VideoPlayer) capte les taps pour ses propres contrôles :
                            // on désactive son hit-testing pour que le tap "plein écran" passe.
                            .allowsHitTesting(false)
                        // Indicateur visuel "plein écran" par-dessus la miniature
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .padding(5)
                            .background(Circle().fill(Color.black.opacity(0.45)))
                    }
                    .frame(width: 100, height: 56)
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture { isFullScreen = true }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Lecture en cours")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(FPTheme.accentBlue)
                    Text(playerViewModel.currentURL?.absoluteString ?? "Inconnu")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: { playerViewModel.player?.timeControlStatus == .playing ? playerViewModel.player?.pause() : playerViewModel.player?.play() }) {
                    Image(systemName: playerViewModel.player?.timeControlStatus == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                }

                Button(action: { isFullScreen = true }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }

                Button(action: { reloadStream() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }

                Button(action: { stopPlaying() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(FPTheme.subtleWhite)
                }
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.bottom, 80) // Just above tab bar
            .shadow(color: Color.black.opacity(0.3), radius: 10, y: 5)
        }
    }

    private func toastView(message: String) -> some View {
        Text(message)
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.black.opacity(0.8)).shadow(radius: 10))
            .padding(.top, 40)
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(100)
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
                ForEach(recentStreams) { item in
                    Button(action: {
                        streamURLString = item.url
                        startPlaying(urlString: item.url)
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(FPTheme.accentBlue.opacity(0.8))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                                
                                Text(item.url)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(FPTheme.subtleWhite)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer()
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

    private func startPlaying(channel: IPTVChannel) {
        addRecentStream(name: channel.name, url: channel.streamURL.absoluteString)
        playerViewModel.startPlaying(url: channel.streamURL)

        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            self.isPlaying = true
        }
    }

    private func startPlaying(urlString: String) {
        let cleanURLString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = URL(string: cleanURLString),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()) else {
            showError("L'URL saisie est invalide. Vérifiez qu'elle commence bien par http:// ou https://.")
            return
        }

        // Si on a déjà un nom dans les favoris pour cette URL, on l'utilise
        let name = favoritesManager.favorites.first(where: { $0.streamURL == url })?.name ?? "Flux manuel"
        addRecentStream(name: name, url: cleanURLString)
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

    private func showToast(_ message: String) {
        toastMessage = message
        withAnimation(.spring()) {
            showingToast = true
        }
        
        // Cacher après 2.5s
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeIn) {
                showingToast = false
            }
        }
    }

    private func addRecentStream(name: String, url: String) {
        var streams = recentStreams
        // Retirer les doublons d'URL
        streams.removeAll { $0.url == url }
        
        // Ajouter en haut
        let newItem = RecentStream(name: name, url: url, date: Date())
        streams.insert(newItem, at: 0)
        
        // Limiter à 10
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
