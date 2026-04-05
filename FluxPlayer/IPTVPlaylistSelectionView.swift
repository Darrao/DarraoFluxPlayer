import SwiftUI

// =============================================================================
// MARK: - IPTVPlaylistSelectionView
// Navigateur de playlists IPTV avec mise en page moderne (cartes glassmorphiques).
// =============================================================================

struct IPTVPlaylistSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    var onSelectChannel: (IPTVChannel) -> Void

    /// Icônes SF Symbols associées aux catégories de chaînes.
    private let categoryIcons: [String: String] = [
        "Animation": "sparkles.tv", "Auto": "car.fill", "Business": "briefcase.fill",
        "Classic": "film.fill", "Comedy": "face.smiling.fill", "Cooking": "fork.knife",
        "Culture": "theatermasks.fill", "Documentary": "doc.text.fill",
        "Education": "graduationcap.fill", "Entertainment": "party.popper.fill",
        "Family": "figure.2.and.child.holdinghands", "General": "tv.fill",
        "Kids": "teddybear.fill", "Legislative": "building.columns.fill",
        "Lifestyle": "heart.fill", "Movies": "popcorn.fill", "Music": "music.note",
        "News": "newspaper.fill", "Outdoor": "leaf.fill", "Public": "antenna.radiowaves.left.and.right",
        "Relax": "moon.stars.fill", "Religious": "book.fill", "Science": "atom",
        "Series": "play.tv.fill", "Shop": "cart.fill", "Sports": "sportscourt.fill",
        "Travel": "airplane", "Weather": "cloud.sun.fill"
    ]

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                FPTheme.backgroundGradient.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 28) {

                        // ── Global ──────────────────────────
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Global", icon: "globe")
                                .padding(.horizontal, 20)

                            NavigationLink(destination: IPTVChannelListView(playlist: IPTVManager.defaultPlaylist, onSelectChannel: onSelectChannel)) {
                                playlistCard(
                                    title: IPTVManager.defaultPlaylist.title,
                                    icon: "globe",
                                    subtitle: "30 000+ chaînes",
                                    gradient: [FPTheme.accentBlue, FPTheme.accentBlue.opacity(0.5)]
                                )
                            }
                            #if os(tvOS)
                            .buttonStyle(.card)
                            .focusSection()
                            #else
                            .buttonStyle(.plain)
                            #endif
                            .padding(.horizontal, 20)
                        }

                        // ── Langues ─────────────────────────
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Langues", icon: "character.bubble")
                                .padding(.horizontal, 20)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(IPTVManager.languages) { language in
                                        NavigationLink(destination: IPTVChannelListView(playlist: language, onSelectChannel: onSelectChannel)) {
                                            languageCard(title: language.title)
                                        }
                                        #if os(tvOS)
                                        .buttonStyle(.card)
                                        #else
                                        .buttonStyle(.plain)
                                        #endif
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 4)
                            }
                            #if os(tvOS)
                            .focusSection()
                            #endif
                        }

                        // ── Catégories (Grille) ─────────────
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Catégories", icon: "square.grid.2x2")
                                .padding(.horizontal, 20)

                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(IPTVManager.categories) { category in
                                    NavigationLink(destination: IPTVChannelListView(playlist: category, onSelectChannel: onSelectChannel)) {
                                        categoryCard(
                                            title: category.title,
                                            icon: categoryIcons[category.title] ?? "folder.fill"
                                        )
                                    }
                                    #if os(tvOS)
                                    .buttonStyle(.card)
                                    #else
                                    .buttonStyle(.plain)
                                    #endif
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        #if os(tvOS)
                        .focusSection()
                        #endif

                        Spacer(minLength: 30)
                    }
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Playlists IPTV")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 650)
        #endif
    }

    // =========================================================================
    // MARK: - Composants de carte
    // =========================================================================

    /// Grande carte pour la playlist globale.
    private func playlistCard(title: String, icon: String, subtitle: String, gradient: [Color]) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(FPTheme.subtleWhite)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(FPTheme.subtleWhite)
        }
        .padding(16)
        .glassBackground(radius: 16)
    }

    /// Carte compacte pour une langue.
    private func languageCard(title: String) -> some View {
        let flag: String = {
            switch title {
            case "Français": return "🇫🇷"
            case "Anglais":  return "🇬🇧"
            case "Japonais": return "🇯🇵"
            default:         return "🌐"
            }
        }()

        return VStack(spacing: 8) {
            Text(flag)
                .font(.system(size: 34))
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: 110, height: 100)
        .glassBackground(radius: 14)
    }

    /// Carte pour une catégorie.
    private func categoryCard(title: String, icon: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(FPTheme.accentBlue)
                .frame(width: 44, height: 44)
                .background(
                    Circle().fill(FPTheme.accentBlue.opacity(0.15))
                )

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .glassBackground(radius: 14)
    }
}
