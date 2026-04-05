import Foundation

struct IPTVChannel: Identifiable, Hashable, Codable {
    var id = UUID()
    let name: String
    let group: String
    let logoURL: URL?
    let streamURL: URL
}

struct IPTVPlaylist: Identifiable, Hashable, Codable {
    var id = UUID()
    let title: String
    let url: String
}

class FavoritesManager: ObservableObject {
    static let shared = FavoritesManager()
    
    @Published var favorites: [IPTVChannel] = [] {
        didSet { saveFavorites() }
    }
    
    init() { loadFavorites() }
    
    func loadFavorites() {
        guard let data = UserDefaults.standard.data(forKey: "savedFavoriteChannels"),
              let decoded = try? JSONDecoder().decode([IPTVChannel].self, from: data) else { return }
        self.favorites = decoded
    }
    
    func saveFavorites() {
        if let encoded = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(encoded, forKey: "savedFavoriteChannels")
        }
    }
    
    func isFavorite(_ channel: IPTVChannel) -> Bool {
        favorites.contains { $0.streamURL == channel.streamURL }
    }
    
    func toggleFavorite(_ channel: IPTVChannel) {
        if isFavorite(channel) {
            favorites.removeAll { $0.streamURL == channel.streamURL }
        } else {
            favorites.append(channel)
        }
    }
    
    func renameFavorite(with streamURL: URL, newName: String) {
        if let index = favorites.firstIndex(where: { $0.streamURL == streamURL }) {
            let old = favorites[index]
            favorites[index] = IPTVChannel(id: old.id, name: newName, group: old.group, logoURL: old.logoURL, streamURL: old.streamURL)
        }
    }
    
    func removeFavorite(with streamURL: URL) {
        favorites.removeAll { $0.streamURL == streamURL }
    }
}

@MainActor
class IPTVManager: ObservableObject {
    @Published var channels: [IPTVChannel] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Playlists globales et spécifiques
    static let defaultPlaylist = IPTVPlaylist(title: "Toutes les chaînes", url: "https://iptv-org.github.io/iptv/index.m3u")
    
    static let languages: [IPTVPlaylist] = [
        IPTVPlaylist(title: "Français", url: "https://iptv-org.github.io/iptv/languages/fra.m3u"),
        IPTVPlaylist(title: "Anglais", url: "https://iptv-org.github.io/iptv/languages/eng.m3u"),
        IPTVPlaylist(title: "Japonais", url: "https://iptv-org.github.io/iptv/languages/jpn.m3u")
    ]
    
    static let categories: [IPTVPlaylist] = {
        let catNames = [
            "Animation", "Auto", "Business", "Classic", "Comedy", "Cooking", "Culture", "Documentary", 
            "Education", "Entertainment", "Family", "General", "Kids", "Legislative", "Lifestyle", 
            "Movies", "Music", "News", "Outdoor", "Public", "Relax", "Religious", "Science", 
            "Series", "Shop", "Sports", "Travel", "Weather"
        ]
        return catNames.map { IPTVPlaylist(title: $0, url: "https://iptv-org.github.io/iptv/categories/\($0.lowercased()).m3u") }
    }()
    
    func loadChannels(from playlistURL: String) async {
        isLoading = true
        errorMessage = nil
        do {
            guard let url = URL(string: playlistURL) else {
                throw URLError(.badURL)
            }
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let content = String(data: data, encoding: .utf8) else {
                throw URLError(.cannotDecodeRawData)
            }
            
            // Le parsing s'effectue hors du thread principal pour éviter de geler l'interface (très lourd si >30k lignes)
            let parsedChannels = await Task.detached {
                var result: [IPTVChannel] = []
                result.reserveCapacity(30000) // Pré-allocation globale pour la performance
                
                var currentName = ""
                var currentGroup = ""
                var currentLogoString = ""
                
                content.enumerateLines { line, _ in
                    let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                    if trimmedLine.isEmpty { return }
                    
                    if trimmedLine.hasPrefix("#EXTINF:") {
                        let infoString = trimmedLine.dropFirst(8)
                        
                        // Parse tvg-logo
                        if let logoRange = infoString.range(of: "tvg-logo=\"") {
                            let restAfterLogo = infoString[logoRange.upperBound...]
                            if let endQuoteRange = restAfterLogo.range(of: "\"") {
                                currentLogoString = String(restAfterLogo[..<endQuoteRange.lowerBound])
                            }
                        } else {
                            currentLogoString = ""
                        }
                        
                        // Parse group-title
                        if let groupRange = infoString.range(of: "group-title=\"") {
                            let restAfterGroup = infoString[groupRange.upperBound...]
                            if let endQuoteRange = restAfterGroup.range(of: "\"") {
                                currentGroup = String(restAfterGroup[..<endQuoteRange.lowerBound])
                            }
                        } else {
                            currentGroup = "Autre"
                        }
                        
                        // Parse name (tout après la dernière virgule)
                        if let commaIndex = infoString.lastIndex(of: ",") {
                            let namePart = infoString[infoString.index(after: commaIndex)...]
                            currentName = String(namePart).trimmingCharacters(in: .whitespaces)
                        } else {
                            currentName = "Chaîne inconnue"
                        }
                        
                    } else if !trimmedLine.hasPrefix("#") {
                        if let streamURL = URL(string: trimmedLine), ["http", "https"].contains(streamURL.scheme?.lowercased()) {
                            let channel = IPTVChannel(
                                name: currentName,
                                group: currentGroup,
                                logoURL: URL(string: currentLogoString),
                                streamURL: streamURL
                            )
                            result.append(channel)
                            
                            // Reset variables
                            currentName = ""
                            currentGroup = ""
                            currentLogoString = ""
                        }
                    }
                }
                return result
            }.value
            
            self.channels = parsedChannels
            self.isLoading = false
            
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }
}
