import SwiftUI

/// Sheet that lists `BackendDiscoveryService.discoveredServers` and lets the
/// user pick one. Selecting a row writes the chosen host:port into
/// `BackendConfigStore.setCustom(...)` and triggers a SocketService reconnect
/// via the closure passed in by `SettingsView`.
///
/// Layout matches the other Settings rows: dark `surfaceLow` cards with gold
/// accent on the selection chevron. While `isBrowsing` is true a small
/// progress indicator sits next to the empty-state copy.
struct BackendDiscoverySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(BackendDiscoveryService.self) private var discovery
    @Environment(BackendConfigStore.self) private var config

    /// Called after the user selects a server and config has been updated.
    /// Settings uses this to drive `socket.reconnectWithCurrentConfig()`.
    let onSelected: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                StellarGlassyBackground()

                ScrollView {
                    VStack(spacing: 12) {
                        if discovery.discoveredServers.isEmpty {
                            emptyState
                        } else {
                            ForEach(discovery.discoveredServers) { server in
                                serverRow(server)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Discover backend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Stellar.Color.gold)
                }
            }
            .onAppear { discovery.startDiscovery() }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            if discovery.isBrowsing {
                ProgressView()
                    .tint(Stellar.Color.gold)
            }
            Text(discovery.isBrowsing ? "Scanning Wi-Fi…" : "No servers found")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Stellar discovers backends that advertise themselves on the local network. If you're sure your backend is running, enter the host manually below.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 24)
        .background(Stellar.Color.surfaceLow, in: RoundedRectangle(cornerRadius: 10))
    }

    private func serverRow(_ server: DiscoveredServer) -> some View {
        Button {
            select(server)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.system(size: 18))
                    .foregroundStyle(Stellar.Color.gold)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("\(server.host):\(server.port)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

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
    }

    private func select(_ server: DiscoveredServer) {
        // Remember the choice as the canonical "custom" config so the user
        // sticks on this backend across launches. Also record it as the most
        // recent discovery so a future `clearCustom()` falls back to here.
        config.recordDiscovered(host: server.host, port: server.port)
        try? config.setCustom(host: server.host, port: server.port, scheme: nil)
        onSelected()
        dismiss()
    }
}
