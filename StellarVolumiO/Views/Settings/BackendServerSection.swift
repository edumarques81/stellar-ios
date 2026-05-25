import SwiftUI

/// "Backend Server" section in SettingsView. Three logical rows:
///
///   1. Current backend display (read-only line of "scheme://host:port").
///   2. "Discover on Wi-Fi" button → presents `BackendDiscoverySheet`.
///   3. Collapsible "Manual entry" — TextField host/port + segmented scheme +
///      Save + Reset-to-default.
///
/// Scoped under a stable `id("backendServerSection")` anchor so the
/// ContentView "Server Settings" button in the connection-failure banner
/// can scroll to it via `ScrollViewReader`.
struct BackendServerSection: View {
    @Environment(SocketService.self) private var socket
    @Environment(BackendConfigStore.self) private var config

    @State private var showDiscoverySheet = false
    @State private var manualExpanded = false
    @State private var hostDraft: String = ""
    @State private var portDraft: String = ""
    @State private var schemeDraft: String = "http"
    @State private var validationError: String? = nil

    /// Anchor id for ScrollViewReader.scrollTo(_:anchor:). Public so
    /// SettingsView can pass it back to ContentView's "Server Settings"
    /// affordance.
    static let scrollAnchor = "backendServerSection"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Backend Server")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .id(Self.scrollAnchor)

            VStack(spacing: 12) {
                currentBackendRow
                discoverButton
                manualEntryRow
            }
        }
    }

    // MARK: - Row 1: current backend

    private var currentBackendRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 14))
                .foregroundStyle(Stellar.Color.gold)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Connected to")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(socket.currentBackendURL)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Stellar.Color.surfaceLow, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Row 2: Discover on Wi-Fi

    private var discoverButton: some View {
        Button {
            showDiscoverySheet = true
        } label: {
            HStack {
                Image(systemName: "wifi")
                    .font(.system(size: 14))
                    .foregroundStyle(Stellar.Color.gold)
                    .frame(width: 22)
                Text("Discover on Wi-Fi")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(minHeight: Stellar.Metric.minTouchTarget)
            .background(Stellar.Color.surfaceLow, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDiscoverySheet) {
            BackendDiscoverySheet(onSelected: {
                // After Bonjour pick, force a clean reconnect against the new
                // host so playback control resumes against the right server.
                socket.reconnectWithCurrentConfig()
            })
        }
    }

    // MARK: - Row 3: Manual entry (collapsible)

    private var manualEntryRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header / toggle row
            Button {
                if !manualExpanded {
                    seedDraftsFromCurrent()
                }
                withAnimation(.easeInOut(duration: 0.18)) {
                    manualExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "keyboard")
                        .font(.system(size: 14))
                        .foregroundStyle(Stellar.Color.gold)
                        .frame(width: 22)
                    Text("Manual entry")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: manualExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .frame(minHeight: Stellar.Metric.minTouchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if manualExpanded {
                manualFields
            }
        }
        .background(Stellar.Color.surfaceLow, in: RoundedRectangle(cornerRadius: 10))
    }

    private var manualFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Scheme
            HStack(spacing: 10) {
                Text("Scheme")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .leading)
                Picker("Scheme", selection: $schemeDraft) {
                    Text("http").tag("http")
                    Text("https").tag("https")
                }
                .pickerStyle(.segmented)
            }

            // Host
            HStack(spacing: 10) {
                Text("Host")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .leading)
                TextField("e.g. 192.168.1.50 or stellar.local", text: $hostDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.URL)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Stellar.Color.baseBackground, in: RoundedRectangle(cornerRadius: 6))
            }

            // Port
            HStack(spacing: 10) {
                Text("Port")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .leading)
                TextField("3000", text: $portDraft)
                    .keyboardType(.numberPad)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Stellar.Color.baseBackground, in: RoundedRectangle(cornerRadius: 6))
            }

            if let validationError {
                Text(validationError)
                    .font(.system(size: 11))
                    .foregroundStyle(Stellar.Color.statusRed)
            }

            HStack(spacing: 10) {
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(Stellar.Color.gold)
                    .foregroundStyle(.black)
                    .controlSize(.small)

                if config.hasCustomConfig {
                    Button("Reset to default", action: resetToDefault)
                        .buttonStyle(.bordered)
                        .tint(Stellar.Color.gold)
                        .controlSize(.small)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    // MARK: - Draft / actions

    private func seedDraftsFromCurrent() {
        hostDraft = config.customHost ?? socket.serverHost
        portDraft = "\(config.customPort ?? socket.serverPort)"
        schemeDraft = config.customScheme ?? socket.serverScheme
        validationError = nil
    }

    private func save() {
        validationError = nil
        let trimmedHost = hostDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            validationError = "Host can't be empty."
            return
        }
        guard let port = Int(portDraft.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...65535).contains(port)
        else {
            validationError = "Port must be a number between 1 and 65535."
            return
        }
        do {
            try config.setCustom(host: trimmedHost, port: port, scheme: schemeDraft)
            socket.reconnectWithCurrentConfig()
            withAnimation { manualExpanded = false }
        } catch BackendConfigStore.ValidationError.emptyHost {
            validationError = "Host can't be empty."
        } catch BackendConfigStore.ValidationError.invalidPort {
            validationError = "Port must be between 1 and 65535."
        } catch BackendConfigStore.ValidationError.invalidScheme {
            validationError = "Scheme must be http or https."
        } catch {
            validationError = error.localizedDescription
        }
    }

    private func resetToDefault() {
        config.clearCustom()
        socket.reconnectWithCurrentConfig()
        seedDraftsFromCurrent()
    }
}
