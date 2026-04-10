import SwiftUI

/// Personalization hub: inspect how scores are computed and manage bounded user tuning nudges.
struct NutrivanceLabsView: View {
    @ObservedObject private var store = NutrivanceTuningStore.shared
    @State private var filterMetric: NutrivanceTuningMetric?
    @State private var sortNewestFirst = true
    @State private var expandedMetrics: Set<NutrivanceTuningMetric> = Set(NutrivanceTuningMetric.allCases)
    @State private var showAddSheet = false

    private var filteredReports: [NutrivanceTuningReport] {
        var list = store.reports
        if let m = filterMetric {
            list = list.filter { $0.metric == m }
        }
        list.sort { sortNewestFirst ? ($0.createdAt > $1.createdAt) : ($0.effectiveStrength > $1.effectiveStrength) }
        return list
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !NutrivanceTuningPlatformPolicy.isHandheldAuthoritativeWriter, !store.pendingIOSOperations.isEmpty {
                    macPendingSyncBanner
                }

                metricGrid

                Text("Tuning reports apply small bounded nudges to displayed Recovery, Strain, and Readiness. Charts and engine inputs stay unchanged; enable “Testing overlay” in Recovery / Readiness / Strain screens to see before vs after.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                reportsList
            }
            .padding()
        }
        .background(GradientBackgrounds().programBuilderMeshBackground())
        .navigationTitle("Nutrivance Labs")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Picker("Filter", selection: $filterMetric) {
                        Text("All metrics").tag(Optional<NutrivanceTuningMetric>.none)
                        ForEach(NutrivanceTuningMetric.allCases) { m in
                            Text(m.displayTitle).tag(Optional(m))
                        }
                    }
                    Toggle("Newest first", isOn: $sortNewestFirst)
                    Toggle("Show testing overlay (global)", isOn: $store.showTestingOverlay)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityLabel("Add tuning report")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            NutrivanceTuningReportEditorSheet(
                existing: nil,
                onSave: { report in
                    store.addReport(report)
                    showAddSheet = false
                },
                onCancel: { showAddSheet = false }
            )
        }
        .onReceiveViewControl(.nutrivanceViewControlNutrivanceLabsNewEntry) {
            showAddSheet = true
        }
    }

    private var macPendingSyncBanner: some View {
        let n = store.pendingIOSOperations.count
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "iphone.and.arrow.forward")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Waiting for iPhone or iPad")
                    .font(.subheadline.weight(.semibold))
                Text("Edits apply here immediately. \(n == 1 ? "One change is" : "\(n) changes are") queued in iCloud for your iPhone or iPad to merge into saved tuning.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.blue.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }

    private var metricGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Metrics")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(NutrivanceTuningMetric.allCases) { metric in
                    metricCard(metric)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private func metricCard(_ metric: NutrivanceTuningMetric) -> some View {
        let enabled = store.isMetricGloballyEnabled(metric)
        let nudges = store.reports.filter { $0.metric == metric && $0.isEnabled }
        let skew = nudges.isEmpty ? "No tunings" : "\(nudges.count) active"
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: metric.icon)
                    .foregroundStyle(enabled ? .orange : .secondary)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { store.isMetricGloballyEnabled(metric) },
                    set: { store.setMetricGloballyEnabled(metric, enabled: $0) }
                ))
                .labelsHidden()
            }
            Text(metric.displayTitle)
                .font(.subheadline.weight(.semibold))
            Text(skew)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(enabled ? Color.orange.opacity(0.08) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(enabled ? Color.orange.opacity(0.25) : Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var reportsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tuning reports")
                .font(.headline)

            if filteredReports.isEmpty {
                ContentUnavailableView(
                    "No tuning reports",
                    systemImage: "slider.horizontal.3",
                    description: Text("Add a report with a short note and direction. Journal / Pathfinder valence tuning can be added in a later update.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ForEach(NutrivanceTuningMetric.allCases) { metric in
                    let rows = filteredReports.filter { $0.metric == metric }
                    if !rows.isEmpty {
                        DisclosureGroup(isExpanded: Binding(
                            get: { expandedMetrics.contains(metric) },
                            set: { isOn in
                                if isOn { expandedMetrics.insert(metric) } else { expandedMetrics.remove(metric) }
                            }
                        )) {
                            ForEach(rows) { report in
                                reportRow(report)
                            }
                        } label: {
                            HStack {
                                Image(systemName: metric.icon)
                                Text(metric.displayTitle)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(rows.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func reportRow(_ report: NutrivanceTuningReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(report.factor.displayTitle)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(report.createdAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(report.userNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            HStack {
                Text("Strength")
                    .font(.caption2)
                Slider(value: Binding(
                    get: { report.effectiveStrength },
                    set: { store.setEffectiveStrength(id: report.id, strength: $0) }
                ), in: 0...1)
                Text(String(format: "%.0f%%", report.effectiveStrength * 100))
                    .font(.caption2.monospacedDigit())
                    .frame(width: 40, alignment: .trailing)
            }
            Toggle("Enabled", isOn: Binding(
                get: { report.isEnabled },
                set: { newVal in
                    var r = report
                    r.isEnabled = newVal
                    store.updateReport(r)
                }
            ))
            .font(.caption)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
        .contextMenu {
            Button(role: .destructive) {
                store.deleteReport(id: report.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Add / edit sheet

private struct NutrivanceTuningReportEditorSheet: View {
    let existing: NutrivanceTuningReport?
    var onSave: (NutrivanceTuningReport) -> Void
    var onCancel: () -> Void

    @State private var metric: NutrivanceTuningMetric = .recovery
    @State private var factor: NutrivanceTuningFactor = .sleep
    @State private var directionUp = true
    @State private var nudge: NutrivanceTuningNudgeLevel = .medium
    @State private var note = ""
    @State private var shortLabel = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Metric") {
                    Picker("Metric", selection: $metric) {
                        ForEach(NutrivanceTuningMetric.allCases) { m in
                            Text(m.displayTitle).tag(m)
                        }
                    }
                    Picker("Factor", selection: $factor) {
                        ForEach(NutrivanceTuningFactor.allCases) { f in
                            Text(f.displayTitle).tag(f)
                        }
                    }
                }
                Section("Nudge") {
                    Toggle("Direction: nudge score up", isOn: $directionUp)
                    Picker("Strength", selection: $nudge) {
                        ForEach(NutrivanceTuningNudgeLevel.allCases, id: \.self) { l in
                            Text(l.label).tag(l)
                        }
                    }
                }
                Section("Reason") {
                    TextField("What feels off? (required)", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                    TextField("Short label for info badge", text: $shortLabel)
                }
            }
            .navigationTitle(existing == nil ? "New tuning" : "Edit tuning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        let label = shortLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "\(factor.displayTitle) tuning"
                            : shortLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                        let rep = NutrivanceTuningReport(
                            id: existing?.id ?? UUID(),
                            createdAt: existing?.createdAt ?? Date(),
                            metric: metric,
                            factor: factor,
                            userDirection: directionUp ? 1 : -1,
                            nudgeLevel: nudge,
                            userNote: trimmed,
                            shortAttributionLabel: label,
                            effectiveStrength: existing?.effectiveStrength ?? 0.55,
                            isEnabled: existing?.isEnabled ?? true
                        )
                        onSave(rep)
                    }
                    .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let e = existing {
                    metric = e.metric
                    factor = e.factor
                    directionUp = e.userDirection >= 0
                    nudge = e.nudgeLevel
                    note = e.userNote
                    shortLabel = e.shortAttributionLabel
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        NutrivanceLabsView()
    }
}
