import Foundation

/// A model whose identity can be rewritten when it turns out not to be unique.
///
/// The library models all synthesise their `id` from wire fields — an album's
/// is its `uri`, an artist's is its name, a track's falls back to its uri — and
/// none of those is guaranteed unique by the backend. `withID` lets the parse
/// boundary hand out a distinct identity without the model having to know why.
protocol StringIdentifiable: Identifiable where ID == String {
    func withID(_ id: String) -> Self
}

extension Array where Element: StringIdentifiable {

    /// The same rows, in the same order, with guaranteed-distinct `id`s.
    ///
    /// SwiftUI's `ForEach` is only defined for unique identities. Handed a
    /// repeat it does not merely render the row twice — it drops views, and the
    /// grid comes back with holes: a tile alone in its column, a screen of
    /// blank space, another tile stranded further down. The library produces
    /// repeats routinely: a classical release tags a different `album_artist`
    /// per track, the backend groups on that, and all of the resulting rows
    /// carry the one folder uri. `To Awaken the Sleeper` is five such rows.
    ///
    /// Uniquify rather than de-duplicate. Those rows are different records —
    /// different personnel, different track counts — and dropping four of them
    /// would hide real music. The first occurrence keeps the natural id so the
    /// common case is untouched; later ones get `<id>#2`, `#3`, … stepping over
    /// any suffix a row already legitimately owns.
    ///
    /// A list that was already unique is returned as-is, so identity — and with
    /// it scroll position and album-art cache hits — stays stable across a
    /// refresh.
    func withUniqueIDs() -> [Element] {
        var used = Set<String>(minimumCapacity: count)
        var collided = false
        var out: [Element] = []
        out.reserveCapacity(count)

        for element in self {
            let base = element.id
            if used.insert(base).inserted {
                out.append(element)
                continue
            }
            collided = true
            var n = 2
            var candidate = "\(base)#\(n)"
            while !used.insert(candidate).inserted {
                n += 1
                candidate = "\(base)#\(n)"
            }
            out.append(element.withID(candidate))
        }

        return collided ? out : self
    }
}

extension LibraryAlbum: StringIdentifiable {
    func withID(_ id: String) -> LibraryAlbum {
        LibraryAlbum(id: id, title: title, artist: artist, uri: uri, albumart: albumart,
                     year: year, trackCount: trackCount, badge: badge, discCount: discCount)
    }
}

extension LibraryArtist: StringIdentifiable {
    func withID(_ id: String) -> LibraryArtist {
        LibraryArtist(id: id, name: name, albumCount: albumCount, artistImage: artistImage)
    }
}

extension Track: StringIdentifiable {
    func withID(_ id: String) -> Track {
        Track(id: id, title: title, artist: artist, album: album, uri: uri,
              trackNumber: trackNumber, duration: duration, albumArt: albumArt,
              source: source, disc: disc)
    }
}
