import SwiftUI

enum LibrarySegment: String, CaseIterable, Identifiable {
    case albums = "Albums"
    case artists = "Artists"
    var id: Self { self }
}

struct LibraryView: View {
    @State private var segment: LibrarySegment = .albums

    var body: some View {
        ZStack {
            StellarGlassyBackground()

            NavigationStack {
                VStack(spacing: 0) {
                    Picker("Library segment", selection: $segment) {
                        ForEach(LibrarySegment.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                    switch segment {
                    case .albums:  AlbumPickerView()
                    case .artists: ArtistPickerView()
                    }
                }
            }
        }
    }
}
