import Foundation

enum Fixtures {

    // Canonical pushState — backend Go shape, all fields present, sane types.
    static let pushStateCanonical: [String: Any] = [
        "status":       "play",
        "title":        "Time",
        "artist":       "Pink Floyd",
        "album":        "The Dark Side of the Moon",
        "albumart":     "/albumart?path=NAS/Pink%20Floyd/Dark%20Side",
        "uri":          "NAS/Pink Floyd/Dark Side/05 Time.flac",
        "service":      "mpd",
        "duration":     413,
        "seek":         134000,
        "volume":       55,
        "mute":         false,
        "shuffle":      false,
        "repeat":       false,
        "repeatSingle": false,
        "trackType":    "flac",
        "samplerate":   "96000",
        "bitdepth":     "24",
        "channels":     2
    ]

    // Loose pushState — fields stringified, optional fields missing, null seek.
    static let pushStateLoose: [String: Any] = [
        "status":     "pause",
        "title":      "Breathe",
        "artist":     "Pink Floyd",
        "album":      "The Dark Side of the Moon",
        "albumart":   "",
        "uri":        "",
        "service":    "mpd",
        "duration":   "163",
        "seek":       NSNull(),
        "volume":     "50",
        "trackType":  "FLAC",
        "samplerate": "44100",
        "bitdepth":   "16",
        "channels":   2
    ]

    // pushState with all fields absent except status — worst-case input.
    static let pushStateMinimal: [String: Any] = [
        "status": "stop"
    ]

    static let pushLibraryAlbumsCanonical: [String: Any] = [
        "albums": [
            ["title": "The Dark Side of the Moon",
             "artist": "Pink Floyd",
             "uri": "NAS/Pink Floyd/Dark Side",
             "albumart": "/albumart?path=NAS/Pink%20Floyd/Dark%20Side",
             "year": 1973,
             "trackCount": 10],
            ["title": "Kind of Blue",
             "artist": "Miles Davis",
             "uri": "NAS/Miles Davis/Kind of Blue",
             "albumart": "/albumart?path=NAS/Miles%20Davis/Kind%20of%20Blue"]
        ],
        "total": 2
    ]

    // Envelope without `total`; mirrors what older backend builds emitted.
    static let pushLibraryAlbumsNoTotal: [String: Any] = [
        "albums": [
            ["title": "Blue", "artist": "Joni Mitchell", "uri": "", "albumart": ""]
        ]
    ]

    static let pushLibraryArtistsCanonical: [String: Any] = [
        "artists": [
            ["name": "Pink Floyd", "albumCount": 14],
            ["name": "Miles Davis", "albumCount": 47, "artistImage": "/artistart?name=Miles%20Davis"]
        ],
        "total": 2
    ]

    static let pushLibraryArtistAlbumsCanonical: [String: Any] = [
        "artist": "Pink Floyd",
        "albums": [
            ["title": "The Wall", "artist": "Pink Floyd",
             "uri": "NAS/Pink Floyd/The Wall",
             "albumart": "/albumart?path=NAS/Pink%20Floyd/The%20Wall"]
        ]
    ]

    // pushLastPlayedAlbum shape per Volumio2-UI CLAUDE.md.
    static let pushLastPlayedAlbumCanonical: [String: Any] = [
        "artist":     "Miles Davis",
        "album":      "Kind of Blue",
        "albumArt":   "/albumart?path=NAS/Miles%20Davis/Kind%20of%20Blue",
        "trackUri":   "NAS/Miles Davis/Kind of Blue/01 So What.flac",
        "trackType":  "flac",
        "sampleRate": "192000",
        "bitDepth":   "24"
    ]

    static let pushLastPlayedAlbumNull: Any = NSNull()

    // Real-backend shape captured 2026-05-24 via socket.io probe — camelCase
    // albumArt, no `total` (it's in `pagination` instead), no `year`. Pins
    // the Task 1.11 fix that switched LibraryAlbum.init?(rawDict:) to read
    // albumArt camelCase.
    static let pushLibraryAlbumsRealBackend: [String: Any] = [
        "albums": [
            ["id": "abc123",
             "title": "Time Out",
             "artist": "Dave Brubeck Quartet",
             "uri": "NAS/Dave Brubeck/Time Out",
             "albumArt": "/albumart?path=NAS/Dave%20Brubeck/Time%20Out",
             "trackCount": 7,
             "source": "mpd"],
            ["id": "def456",
             "title": "A Love Supreme",
             "artist": "John Coltrane",
             "uri": "NAS/John Coltrane/A Love Supreme",
             "albumArt": "/albumart?path=NAS/John%20Coltrane/A%20Love%20Supreme",
             "trackCount": 4]
        ],
        "pagination": ["total": 72, "limit": 500, "offset": 0]
    ]
}
