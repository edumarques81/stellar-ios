import SwiftUI

/// Drop-box ingest — the phone's trigger for `stellar-ingest` on the Pi.
///
/// Two taps by design: "Review import" runs the dry run and raises the plan
/// sheet; "Import" commits it. The whole section hides itself when the backend
/// reports the script is unavailable, so an older Pi shows nothing rather than
/// a button that can only fail.
///
/// The plan and the result arrive as broadcasts, so a run started on the LCD
/// raises this sheet too. That is deliberate — both surfaces must agree about
/// what is still waiting in the inbox.
struct IngestSection: View {
    @Environment(IngestStore.self) private var ingest

    var body: some View {
        if ingest.isAvailable {
            card
                .sheet(isPresented: sheetBinding) { IngestSheet() }
        }
    }

    // Presented for either the plan or the result; `IngestSheet` decides which
    // to render from live store state, so a commit that swaps preview→result
    // updates in place instead of dismissing and re-presenting.
    private var sheetBinding: Binding<Bool> {
        Binding(
            get: { ingest.preview != nil || ingest.result != nil },
            set: { shown in
                guard !shown else { return }
                if ingest.result != nil {
                    ingest.dismiss()
                } else {
                    ingest.cancel()
                }
            }
        )
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Add music")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(statusLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                ingest.previewInbox()
            } label: {
                HStack(spacing: 8) {
                    if ingest.phase == .previewing {
                        ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                    }
                    Text(ingest.phase == .previewing ? "Checking…" : "Review import")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity, minHeight: Stellar.Metric.minTouchTarget)
                .foregroundStyle(canPreview ? Stellar.Color.gold : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(canPreview ? Stellar.Color.gold : Stellar.Color.separator, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(!canPreview)

            Button {
                ingest.requestStatus()
            } label: {
                Text("Check inbox again")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: Stellar.Metric.minTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(ingest.isBusy)

            if let err = ingest.lastError {
                Text(err.error)
                    .font(.system(size: 11))
                    .foregroundStyle(Stellar.Color.statusRed)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Stellar.Color.surfaceLow, in: RoundedRectangle(cornerRadius: 10))
    }

    private var canPreview: Bool { !ingest.isBusy && ingest.hasItems }

    private var statusLine: String {
        switch ingest.phase {
        case .previewing: return "Checking the inbox…"
        case .committing: return "Importing — this can take a few minutes."
        case .idle:       break
        }
        if ingest.status?.busy == true { return "An import is already running." }
        let count = ingest.status?.count ?? 0
        if count == 0 { return "Nothing waiting. Drop albums into the Inbox share." }
        return "\(count) \(count == 1 ? "folder" : "folders") waiting in the inbox."
    }
}

// MARK: - Sheet

/// Plan-then-result sheet. Reads the store live rather than capturing a report
/// at presentation time, so `commit()` swapping preview→result redraws here.
struct IngestSheet: View {
    @Environment(IngestStore.self) private var ingest

    var body: some View {
        NavigationStack {
            Group {
                if let result = ingest.result {
                    body(for: result, isResult: true)
                } else if let preview = ingest.preview {
                    body(for: preview, isResult: false)
                } else {
                    // Transient: the sheet's isPresented binding is about to
                    // flip false. Render nothing rather than an empty list.
                    Color.clear
                }
            }
            .background(Stellar.Color.baseBackground)
            .navigationTitle(ingest.result == nil ? "Import from inbox" : "Import finished")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func body(for report: IngestReport, isResult: Bool) -> some View {
        VStack(spacing: 0) {
            summaryHeader(for: report, isResult: isResult)

            List {
                ForEach(IngestSection.sorted(report.items)) { item in
                    IngestItemRow(item: item, showTarget: !isResult)
                        .listRowBackground(Stellar.Color.surfaceLow)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            actions(isResult: isResult)
        }
    }

    @ViewBuilder
    private func summaryHeader(for report: IngestReport, isResult: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if isResult {
                if report.error.isEmpty {
                    Text("\(report.summary.ingested) imported · \(report.summary.refused) refused · \(report.summary.skipped) skipped"
                         + (report.summary.tagFailures > 0 ? " · \(report.summary.tagFailures) tag failure(s)" : ""))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    Text(report.error)
                        .font(.system(size: 12))
                        .foregroundStyle(Stellar.Color.statusRed)
                }
                if report.summary.audioAltered > 0 {
                    Text("\(report.summary.audioAltered) file(s) changed audio checksum — check before playing.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Stellar.Color.statusRed)
                }
            } else {
                Text("\(report.summary.wouldIngest) of \(report.summary.total) will be imported. Nothing is copied until you confirm.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if let err = ingest.lastError {
                Text(err.error)
                    .font(.system(size: 12))
                    .foregroundStyle(Stellar.Color.statusRed)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func actions(isResult: Bool) -> some View {
        HStack(spacing: 12) {
            if isResult {
                Button("Done") { ingest.dismiss() }
                    .buttonStyle(IngestPrimaryButtonStyle(enabled: true))
            } else {
                Button("Cancel") { ingest.cancel() }
                    .buttonStyle(IngestSecondaryButtonStyle())
                    .disabled(ingest.phase == .committing)

                Button(ingest.phase == .committing ? "Importing…" : "Import") {
                    ingest.commit()
                }
                .buttonStyle(IngestPrimaryButtonStyle(enabled: ingest.canCommit))
                .disabled(!ingest.canCommit)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Stellar.Color.baseBackground)
    }
}

// MARK: - Row

struct IngestItemRow: View {
    let item: IngestItem
    let showTarget: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.name)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(item.status.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(statusColor)
            }
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            // The backend's `reason` often spells the destination out, so only
            // add the arrow line when it would say something new.
            if showTarget, !item.target.isEmpty, !detail.contains(item.target) {
                Text("→ \(item.target)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var statusColor: Color {
        switch item.status {
        case "refused", "skipped":         return Stellar.Color.statusRed
        case "ingested", "would-ingest":   return Stellar.Color.gold
        default:                            return .secondary
        }
    }

    /// One line of detail under the folder name, or "" when there is nothing
    /// to add. Mirrors `IngestPanel.svelte`'s `detail()`.
    private var detail: String {
        var bits: [String] = []
        if !item.reason.isEmpty { bits.append(item.reason) }
        if item.audioFiles > 0 {
            bits.append("\(item.audioFiles) \(item.audioFiles == 1 ? "track" : "tracks")")
        }
        if !item.tagged.isEmpty {
            bits.append("tagged from \(item.mbRelease.isEmpty ? "MusicBrainz" : item.mbRelease)")
        }
        if !item.art.isEmpty { bits.append("art: \(item.art)") }
        if !item.tagFailures.isEmpty { bits.append("\(item.tagFailures.count) tag(s) did not stick") }
        if !item.md5Mismatches.isEmpty {
            bits.append("\(item.md5Mismatches.count) audio checksum mismatch")
        }
        return bits.joined(separator: " · ")
    }
}

// MARK: - Helpers

extension IngestSection {
    /// Worst-first: a refusal is the thing worth reading.
    static func sorted(_ list: [IngestItem]) -> [IngestItem] {
        let order: [String: Int] = ["refused": 0, "skipped": 1, "would-ingest": 2, "ingested": 3]
        return list.enumerated()
            .sorted { a, b in
                let ra = order[a.element.status] ?? 9
                let rb = order[b.element.status] ?? 9
                // Stable: fall back to the original index so equal statuses
                // keep the order the backend reported them in.
                return ra == rb ? a.offset < b.offset : ra < rb
            }
            .map(\.element)
    }
}

private struct IngestPrimaryButtonStyle: ButtonStyle {
    let enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(enabled ? Stellar.Color.baseBackground : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: Stellar.Metric.minTouchTarget)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(enabled ? Stellar.Color.gold : Stellar.Color.separator)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private struct IngestSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity, minHeight: Stellar.Metric.minTouchTarget)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Stellar.Color.separator, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
