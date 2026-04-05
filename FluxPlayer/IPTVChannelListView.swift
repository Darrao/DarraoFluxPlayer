import SwiftUI

// =============================================================================
// MARK: - IPTVChannelListView
// Liste des chaînes IPTV avec recherche, filtrage par catégorie,
// et design moderne (fond sombre, cartes glassmorphiques, focus tvOS).
// =============================================================================

struct IPTVChannelListView: View {
    let playlist: IPTVPlaylist
    @StateObject private var manager = IPTVManager()
    @ObservedObject private var favorites = FavoritesManager.shared
    @State private var searchText = ""
    @State private var selectedCategory: String = "Toutes"

    // Pour l'action sheet (favoris / lecture)
    @State private var selectedChannel: IPTVChannel?
    @State private var showingActionDialog = false

    // Callback quand l'utilisateur choisit une chaîne
    var onSelectChannel: (String) -> Void

    var availableCategories: [String] {
        var allCats = Set<String>()
        for channel in manager.channels {
            let catString = channel.group.isEmpty ? "Autre" : channel.group
            let splits = catString.split(separator: ";").map { String($0).trimmingCharacters(in: .whitespaces) }
            for split in splits {
                allCats.insert(split)
            }
        }
        return ["Toutes"] + allCats.sorted()
    }

    var textFilteredChannels: [IPTVChannel] {
        var filtered = manager.channels

        if selectedCategory != "Toutes" {
            filtered = filtered.filter { channel in
                let catString = channel.group.isEmpty ? "Autre" : channel.group
                let splits = catString.split(separator: ";").map { String($0).trimmingCharacters(in: .whitespaces) }
                return splits.contains(selectedCategory)
            }
        }

        if !searchText.isEmpty {
            let searchTerms = searchText.split(separator: " ")
            filtered = filtered.filter { channel in
                searchTerms.allSatisfy { term in
                    channel.name.localizedCaseInsensitiveContains(term) ||
                    channel.group.localizedCaseInsensitiveContains(term)
                }
            }
        }
        return filtered
    }

    var groupedChannels: [(String, [IPTVChannel])] {
        let channels = textFilteredChannels
        let grouped = Dictionary(grouping: channels, by: { $0.group })
        return grouped.sorted { $0.key < $1.key }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FPTheme.backgroundGradient.ignoresSafeArea()

                Group {
                    if manager.isLoading {
                        loadingView
                    } else if let error = manager.errorMessage {
                        errorView(error)
                    } else {
                        channelListView
                    }
                }
            }
            .navigationTitle(playlist.title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 6) {
                        Image(systemName: "tv")
                            .font(.system(size: 12))
                        Text("\(manager.channels.count) chaînes")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(FPTheme.subtleWhite)
                }
            }
            .task {
                if manager.channels.isEmpty {
                    await manager.loadChannels(from: playlist.url)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 600)
        #endif
    }

    // =========================================================================
    // MARK: - Sous-vues
    // =========================================================================

    /// Indicateur de chargement avec animation.
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(FPTheme.accentBlue)
            Text("Chargement des chaînes…")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(FPTheme.subtleWhite)
        }
    }

    /// Vue d'erreur avec bouton Réessayer.
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundColor(FPTheme.warningYellow)

            Text("Erreur")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)

            Text(error)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(FPTheme.subtleWhite)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: {
                Task { await manager.loadChannels(from: playlist.url) }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Réessayer")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Capsule().fill(FPTheme.accentBlue))
            }
            #if os(tvOS)
            .buttonStyle(.card)
            #else
            .buttonStyle(.plain)
            #endif
        }
        .padding()
    }

    /// Liste des chaînes avec filtre et recherche.
    private var channelListView: some View {
        List {
            // Filtre par catégorie
            if availableCategories.count > 2 {
                Section {
                    Picker("Filtrer par catégorie", selection: $selectedCategory) {
                        ForEach(availableCategories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                    #if os(tvOS) || os(iOS)
                    .pickerStyle(.navigationLink)
                    #endif
                }
            }

            // Groupes de chaînes
            ForEach(groupedChannels, id: \.0) { groupName, channelsInGroup in
                Section(header: sectionHeader(groupName)) {
                    ForEach(channelsInGroup) { channel in
                        Button(action: {
                            selectedChannel = channel
                            showingActionDialog = true
                        }) {
                            channelRow(channel)
                        }
                        #if os(tvOS)
                        .buttonStyle(.card)
                        #endif
                    }
                }
            }
        }
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
        .searchable(text: $searchText, prompt: "Rechercher une chaîne (ex: France 24)")
        .confirmationDialog("Options de la chaîne", isPresented: $showingActionDialog, presenting: selectedChannel) { channel in
            Button("Lire la chaîne") {
                onSelectChannel(channel.streamURL.absoluteString)
            }
            Button(favorites.isFavorite(channel) ? "Retirer des favoris" : "Ajouter aux favoris") {
                favorites.toggleFavorite(channel)
            }
            Button("Annuler", role: .cancel) {}
        } message: { channel in
            Text(channel.name)
        }
    }

    /// En-tête de section pour un groupe de chaînes.
    private func sectionHeader(_ name: String) -> some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    /// Ligne individuelle d'une chaîne.
    private func channelRow(_ channel: IPTVChannel) -> some View {
        HStack(spacing: 14) {
            // Logo
            channelLogo(channel)

            // Infos textuelles
            VStack(alignment: .leading, spacing: 4) {
                Text(channel.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(channel.group)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(FPTheme.subtleWhite)
                    .lineLimit(1)
            }

            Spacer()

            // Indicateur favori
            if favorites.isFavorite(channel) {
                Image(systemName: "star.fill")
                    .font(.system(size: 14))
                    .foregroundColor(FPTheme.warningYellow)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(FPTheme.subtleWhite)
        }
        .padding(.vertical, 4)
    }

    /// Logo de la chaîne avec fallback.
    private func channelLogo(_ channel: IPTVChannel) -> some View {
        Group {
            if let logoURL = channel.logoURL {
                AsyncImage(url: logoURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFit()
                    } else if phase.error != nil {
                        logoPlaceholder
                    } else {
                        ProgressView()
                            .frame(width: 44, height: 44)
                    }
                }
            } else {
                logoPlaceholder
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var logoPlaceholder: some View {
        Image(systemName: "tv")
            .font(.system(size: 18))
            .foregroundColor(FPTheme.subtleWhite)
            .frame(width: 44, height: 44)
    }
}
