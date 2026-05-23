import SwiftUI

struct LibraryView: View {
    enum Section: String, CaseIterable, Identifiable {
        case albums = "Albums"
        case artists = "Artists"
        var id: String { rawValue }
    }

    @State private var section: Section = .albums

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Library section", selection: $section) {
                    ForEach(Section.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().background(Color.mdOutlineVariant.opacity(0.4))

                switch section {
                case .albums:
                    AlbumPickerView()
                case .artists:
                    ArtistPickerView()
                }
            }
            .background(Color.mdBackground.ignoresSafeArea())
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.mdBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
