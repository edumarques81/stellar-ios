import Foundation
import Observation

// MARK: - Browse / Favourites data models

struct BrowseItem: Identifiable, Decodable {
    var id: String { uri }
    let service: String?
    let type: String?
    let title: String?
    let name: String?   // Volumio sometimes sends 'name' instead of 'title'
    let artist: String?
    let album: String?
    let uri: String
    let albumart: String?
    let duration: Int?

    /// Display title (prefer 'title', fall back to 'name')
    var displayTitle: String { title ?? name ?? "Unknown" }
}

private struct BrowseList: Decodable {
    let items: [BrowseItem]?
}

private struct BrowseNavigation: Decodable {
    let lists: [BrowseList]
}

private struct BrowseResponse: Decodable {
    let navigation: BrowseNavigation
}

// MARK: - FavoritesStore

@Observable
final class FavoritesStore {

    private(set) var items: [BrowseItem] = []
    private(set) var isLoading: Bool = false
    private(set) var error: String? = nil

    private var pendingFetch = false
    private var bound = false

    // MARK: - Bind to socket (idempotent)

    func bind(to socket: SocketService) {
        guard !bound else { return }
        bound = true

        // Capture pushBrowseLibrary only when we triggered the fetch
        socket.on("pushBrowseLibrary") { [weak self] (response: BrowseResponse) in
            guard let self, self.pendingFetch else { return }
            self.pendingFetch = false
            self.isLoading = false
            self.error = nil

            let allItems = response.navigation.lists.flatMap { $0.items ?? [] }
            self.items = allItems
        }
    }

    // MARK: - Actions

    func fetch(using socket: SocketService) {
        pendingFetch = true
        isLoading = true
        error = nil
        socket.emit("browseLibrary", data: [["uri": "favourites"]])
    }

    func play(_ item: BrowseItem, using socket: SocketService) {
        socket.emit("replaceAndPlay", data: [[
            "service": item.service ?? "mpd",
            "type": item.type ?? "song",
            "title": item.displayTitle,
            "uri": item.uri,
        ]])
    }

    func addToQueue(_ item: BrowseItem, using socket: SocketService) {
        socket.emit("addToQueue", data: [[
            "service": item.service ?? "mpd",
            "type": item.type ?? "song",
            "title": item.displayTitle,
            "uri": item.uri,
        ]])
    }

    func removeFavorite(_ item: BrowseItem, using socket: SocketService) {
        // Optimistic local removal
        items.removeAll { $0.uri == item.uri }
        socket.emit("removeFromFavourites", data: [[
            "service": item.service ?? "mpd",
            "uri": item.uri,
        ]])
    }

    func playAll(using socket: SocketService) {
        socket.emit("playFavourites")
    }
}
