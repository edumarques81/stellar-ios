import SwiftUI

struct SettingsView: View {
    @Environment(SocketService.self) private var socket
    @Environment(AudioEngineStore.self) private var audioEngine
    @Environment(ThemeStore.self) private var themeStore
    @Environment(QobuzStore.self) private var qobuz

    @AppStorage("serverHost") private var serverHost = "stellar.local"
    @AppStorage("serverPort") private var serverPort = 3000

    @State private var editingHost = false
    @State private var tempHost = "stellar.local"
    @State private var qobuzEmail = ""
    @State private var qobuzPassword = ""

    var body: some View {
        let _ = themeStore.theme

        NavigationStack {
            ZStack {
                Color.mdBackground.ignoresSafeArea()

                Form {
                    // Appearance
                    Section("Appearance") {
                        ForEach(StellarTheme.allCases) { t in
                            Button {
                                themeStore.theme = t
                            } label: {
                                HStack(spacing: 14) {
                                    // Colour dot
                                    Circle()
                                        .fill(t.accentColor)
                                        .frame(width: 22, height: 22)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(.mdOutlineVariant, lineWidth: 1)
                                        )

                                    // Icon + label
                                    Label(t.displayName, systemImage: t.icon)
                                        .foregroundStyle(.mdOnSurface)

                                    Spacer()

                                    // Checkmark if selected
                                    if themeStore.theme == t {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(t.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowBackground(Color.mdSurfaceContainerLow)

                    // Qobuz
                    Section("Qobuz") {
                        if qobuz.isLoggedIn {
                            // Logged-in state
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 10, height: 10)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(qobuz.email ?? "Connected")
                                        .font(StellarFont.bodyMedium)
                                        .foregroundStyle(.mdOnSurface)
                                    if let sub = qobuz.subscription {
                                        Text(sub)
                                            .font(StellarFont.labelSmall)
                                            .foregroundStyle(.mdOnSurfaceVariant)
                                    }
                                }
                            }

                            Button(role: .destructive) {
                                qobuz.logout(via: socket)
                            } label: {
                                if qobuz.isLoading {
                                    ProgressView().tint(.mdPrimary)
                                } else {
                                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                                        .foregroundStyle(.mdError)
                                }
                            }
                            .disabled(qobuz.isLoading)
                        } else {
                            // Login form
                            TextField("Email", text: $qobuzEmail)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .foregroundStyle(.mdOnSurface)

                            SecureField("Password", text: $qobuzPassword)
                                .foregroundStyle(.mdOnSurface)

                            if let err = qobuz.error {
                                Text(err)
                                    .font(StellarFont.labelSmall)
                                    .foregroundStyle(.mdError)
                            }

                            Button {
                                qobuz.login(email: qobuzEmail, password: qobuzPassword, via: socket)
                            } label: {
                                if qobuz.isLoading {
                                    ProgressView().tint(.mdPrimary)
                                } else {
                                    Label("Sign in to Qobuz", systemImage: "music.note")
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .foregroundStyle(.mdPrimary)
                                }
                            }
                            .disabled(qobuzEmail.isEmpty || qobuzPassword.isEmpty || qobuz.isLoading)
                        }
                    }
                    .listRowBackground(Color.mdSurfaceContainerLow)

                    // Connection
                    Section("Connection") {
                        HStack {
                            Label("Server", systemImage: "server.rack")
                                .foregroundStyle(.mdOnSurface)
                            Spacer()
                            Text("\(serverHost):\(serverPort)")
                                .font(StellarFont.bodyMedium)
                                .foregroundStyle(.mdOnSurfaceVariant)
                        }

                        HStack {
                            Label("Status", systemImage: "wifi")
                                .foregroundStyle(.mdOnSurface)
                            Spacer()
                            ConnectionStatusBadge(state: socket.connectionState)
                        }

                        Button("Reconnect") { socket.connect(host: serverHost, port: serverPort) }
                            .foregroundStyle(.mdPrimary)
                    }
                    .listRowBackground(Color.mdSurfaceContainerLow)

                    // Audio Engine
                    Section("Audio Engine") {
                        HStack {
                            Label("Active", systemImage: "speaker.wave.2")
                                .foregroundStyle(.mdOnSurface)
                            Spacer()
                            Text(audioEngine.activeEngine.displayName)
                                .foregroundStyle(audioEngine.isAudirvanaActive ? .audirvanaAccent : .mdPrimary)
                                .font(StellarFont.labelLarge)
                        }

                        Button {
                            audioEngine.switchTo(.mpd, via: socket)
                        } label: {
                            Label("Switch to MPD", systemImage: "play.square")
                        }
                        .foregroundStyle(audioEngine.activeEngine == .mpd ? .mdOnSurfaceVariant : .mdPrimary)
                        .disabled(audioEngine.activeEngine == .mpd || audioEngine.isSwitching)

                        Button {
                            audioEngine.switchTo(.audirvana, via: socket)
                        } label: {
                            Label("Switch to Audirvana", systemImage: "headphones")
                        }
                        .foregroundStyle(audioEngine.isAudirvanaActive ? .mdOnSurfaceVariant : Color.audirvanaAccent)
                        .disabled(audioEngine.isAudirvanaActive || audioEngine.isSwitching)
                    }
                    .listRowBackground(Color.mdSurfaceContainerLow)

                    // About
                    Section("About") {
                        LabeledContent("App", value: "Stellar VolumiO")
                        LabeledContent("Version", value: "1.0.0")
                        LabeledContent("Backend", value: "Stellar Volumio Go Server")
                    }
                    .foregroundStyle(.mdOnSurface)
                    .listRowBackground(Color.mdSurfaceContainerLow)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.mdSurfaceContainer, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

private struct ConnectionStatusBadge: View {
    let state: ConnectionState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            Text(label)
                .font(StellarFont.labelMedium)
                .foregroundStyle(dotColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(dotColor.opacity(0.1), in: Capsule())
    }

    private var dotColor: Color {
        switch state {
        case .connected: return .mdSuccess
        case .connecting: return .yellow
        case .disconnected: return .mdOnSurfaceVariant
        case .error: return .mdError
        }
    }

    private var label: String {
        switch state {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .disconnected: return "Disconnected"
        case .error: return "Error"
        }
    }
}
