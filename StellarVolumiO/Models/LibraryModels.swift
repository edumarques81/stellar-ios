import Foundation

// MARK: - Library Album
// Wire shape for `pushLibraryAlbums` + `pushLibraryArtistAlbums`. Matches the
// payload produced by stellar backend `internal/transport/socketio/library_handlers.go`.

struct LibraryAlbum: Codable, Identifiable, Equatable, Hashable {
    let id: String       // synthetic — backend uses uri OR artist|album, see init(from:)
    let title: String
    let artist: String
    let uri: String      // playable URI; empty for derived-from-tracks rows
    let albumart: String // path or URL ('/albumart?path=...' shape)
    let year: Int?
    let trackCount: Int?

    enum CodingKeys: String, CodingKey {
        case title, artist, uri, albumart, year, trackCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title       = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        artist      = try c.decodeIfPresent(String.self, forKey: .artist) ?? ""
        uri         = try c.decodeIfPresent(String.self, forKey: .uri) ?? ""
        albumart    = try c.decodeIfPresent(String.self, forKey: .albumart) ?? ""
        year        = try c.decodeIfPresent(Int.self, forKey: .year)
        trackCount  = try c.decodeIfPresent(Int.self, forKey: .trackCount)
        id          = uri.isEmpty ? "\(artist)|\(title)" : uri
    }

    init(id: String, title: String, artist: String, uri: String, albumart: String, year: Int? = nil, trackCount: Int? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.uri = uri
        self.albumart = albumart
        self.year = year
        self.trackCount = trackCount
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encode(artist, forKey: .artist)
        try c.encode(uri, forKey: .uri)
        try c.encode(albumart, forKey: .albumart)
        try c.encodeIfPresent(year, forKey: .year)
        try c.encodeIfPresent(trackCount, forKey: .trackCount)
    }
}

// MARK: - Library Artist
struct LibraryArtist: Codable, Identifiable, Equatable, Hashable {
    let id: String      // synthetic from name (backend doesn't always send a stable id)
    let name: String
    let albumCount: Int?
    let artistImage: String?    // optional artist image path; backend may omit

    enum CodingKeys: String, CodingKey {
        case id, name, albumCount, artistImage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decodedName = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        name = decodedName
        albumCount  = try c.decodeIfPresent(Int.self, forKey: .albumCount)
        artistImage = try c.decodeIfPresent(String.self, forKey: .artistImage)
        let decodedId = try c.decodeIfPresent(String.self, forKey: .id)
        id = decodedId ?? decodedName
    }

    init(id: String, name: String, albumCount: Int? = nil, artistImage: String? = nil) {
        self.id = id
        self.name = name
        self.albumCount = albumCount
        self.artistImage = artistImage
    }
}

// MARK: - Wire envelopes (push* payloads)

struct PushLibraryAlbums: Codable {
    let albums: [LibraryAlbum]
    let total: Int?
}

struct PushLibraryArtists: Codable {
    let artists: [LibraryArtist]
    let total: Int?
}

struct PushLibraryArtistAlbums: Codable {
    let artist: String?
    let albums: [LibraryAlbum]
}

// MARK: - LCD Status
struct LcdStatus: Decodable, Equatable {
    let isOn: Bool

    enum CodingKeys: String, CodingKey {
        case isOn
        case state          // some firmware sends 'state' string instead
        case on             // ...or 'on' bool
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try c.decodeIfPresent(Bool.self, forKey: .isOn) {
            isOn = v
        } else if let v = try c.decodeIfPresent(Bool.self, forKey: .on) {
            isOn = v
        } else if let s = try c.decodeIfPresent(String.self, forKey: .state) {
            isOn = (s.lowercased() == "on" || s.lowercased() == "wake")
        } else {
            isOn = true
        }
    }

    init(isOn: Bool) { self.isOn = isOn }
}

// MARK: - Tolerant envelope parsers
//
// Each `init(rawDict:)` accepts the raw [String: Any] that came out of
// Socket.IO and reads the nested album / artist dicts directly (no
// JSONSerialization round-trip). Missing keys fall back to "" for strings
// or nil for Optionals. The per-row initialisers (LibraryAlbum/LibraryArtist
// `init?(rawDict:)`, defined below) carry the same defensive defaults so
// a malformed row produces a row with empty fields rather than a parse
// failure for the whole envelope.

extension PushLibraryAlbums {
    init?(rawDict d: [String: Any]) {
        let rawAlbums = d["albums"] as? [[String: Any]] ?? []
        let albums = rawAlbums.compactMap { LibraryAlbum(rawDict: $0) }
        let total = d["total"] as? Int
        self.albums = albums
        self.total = total
    }
}

extension PushLibraryArtists {
    init?(rawDict d: [String: Any]) {
        let rawArtists = d["artists"] as? [[String: Any]] ?? []
        let artists = rawArtists.compactMap { LibraryArtist(rawDict: $0) }
        let total = d["total"] as? Int
        self.artists = artists
        self.total = total
    }
}

extension PushLibraryArtistAlbums {
    init?(rawDict d: [String: Any]) {
        let rawAlbums = d["albums"] as? [[String: Any]] ?? []
        let albums = rawAlbums.compactMap { LibraryAlbum(rawDict: $0) }
        let artist = d["artist"] as? String
        self.artist = artist
        self.albums = albums
    }
}

extension LibraryAlbum {
    /// Dict-based tolerant init — mirrors the existing JSONDecoder
    /// `init(from:)` shape but reads the dict directly.
    init?(rawDict d: [String: Any]) {
        let title    = d["title"]    as? String ?? ""
        let artist   = d["artist"]   as? String ?? ""
        let uri      = d["uri"]      as? String ?? ""
        let albumart = (d["albumArt"] as? String) ?? (d["albumart"] as? String) ?? ""
        let year     = d["year"] as? Int
        let trackCount = d["trackCount"] as? Int
        let id = uri.isEmpty ? "\(artist)|\(title)" : uri
        self.init(id: id, title: title, artist: artist, uri: uri,
                  albumart: albumart, year: year, trackCount: trackCount)
    }
}

extension LibraryArtist {
    init?(rawDict d: [String: Any]) {
        let name = d["name"] as? String ?? ""
        let id   = (d["id"] as? String) ?? name
        let albumCount  = d["albumCount"]  as? Int
        let artistImage = d["artistImage"] as? String
        self.init(id: id, name: name, albumCount: albumCount, artistImage: artistImage)
    }
}
