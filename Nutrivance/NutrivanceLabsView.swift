import SwiftUI

/// Personalization hub: inspect how scores are computed and manage bounded user tuning nudges.
struct NutrivanceLabsView: View {
    @ObservedObject private var store = NutrivanceTuningStore.shared
    @ObservedObject private var engine = HealthStateEngine.shared
    @Namespace private var labNamespace
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedMetric: NutrivanceTuningMetric?
    @State private var selectedReport: NutrivanceTuningReport?
    @State private var metricForNewReport: NutrivanceTuningMetric?
    @State private var sortNewestFirst = true
    @State private var showAddSheet = false

    private var activeMetricCount: Int {
        NutrivanceTuningMetric.allCases.filter { store.isMetricGloballyEnabled($0) }.count
    }

    private var activeReportCount: Int {
        store.reports.filter(\.isEnabled).count
    }

    private var bodyCopy: String {
        "Papers are display-layer nudges layered on top of live Recovery, Strain, and Readiness calculations. The raw engine formula stays intact; the lab lets people see, tune, and question the model output."
    }

    var body: some View {
        ZStack {
            GradientBackgrounds().programBuilderMeshBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !NutrivanceTuningPlatformPolicy.isHandheldAuthoritativeWriter, !store.pendingIOSOperations.isEmpty {
                        macPendingSyncBanner
                    }

                    deskHero
                    deskControls
                    metricDesk
                    deskFootnote
                }
                .padding()
                .padding(.bottom, 28)
            }

            if let metric = selectedMetric {
                NavigationLink(destination: MetricStackDetailView(
                    metric: metric,
                    reports: sortedReports(for: metric),
                    snapshot: metricSnapshot(for: metric),
                    store: store,
                    namespace: labNamespace,
                    onSelectReport: { report in
                        selectedReport = report
                    },
                    onAddReport: {
                        metricForNewReport = metric
                        showAddSheet = true
                    },
                    sortNewestFirst: sortNewestFirst
                )) {
                    EmptyView()
                }
                .hidden()
                .opacity(0)
            }
        }
        .background(
            NavigationLink(destination: Group {
                if let metric = selectedMetric {
                    MetricStackDetailView(
                        metric: metric,
                        reports: sortedReports(for: metric),
                        snapshot: metricSnapshot(for: metric),
                        store: store,
                        namespace: labNamespace,
                        onSelectReport: { report in
                            selectedReport = report
                        },
                        onAddReport: {
                            metricForNewReport = metric
                            showAddSheet = true
                        },
                        sortNewestFirst: sortNewestFirst
                    )
                } else {
                    EmptyView()
                }
            }, isActive: Binding(
                get: { selectedMetric != nil },
                set: { if !$0 { selectedMetric = nil } }
            )) {
                EmptyView()
            }
            .hidden()
        )
        .navigationTitle("Nutrivance Labs")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Picker("Paper order", selection: $sortNewestFirst) {
                        Text("Newest first").tag(true)
                        Text("Strongest first").tag(false)
                    }
                    Toggle("Show testing overlay", isOn: $store.showTestingOverlay)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    metricForNewReport = selectedMetric
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityLabel("Add tuning report")
            }
        }
        .sheet(isPresented: $showAddSheet, onDismiss: { metricForNewReport = nil }) {
            NutrivanceTuningReportEditorSheet(
                existing: nil,
                seedMetric: metricForNewReport,
                onSave: { report in
                    store.addReport(report)
                    selectedMetric = report.metric
                    metricForNewReport = nil
                    showAddSheet = false
                },
                onCancel: {
                    metricForNewReport = nil
                    showAddSheet = false
                }
            )
        }
        .sheet(item: $selectedReport) { report in
            TuningReportDetailView(reportID: report.id)
        }
        .animation(.spring(response: 0.44, dampingFraction: 0.86), value: store.reports)
        .animation(.spring(response: 0.44, dampingFraction: 0.86), value: selectedMetric)
        .onReceiveViewControl(.nutrivanceViewControlNutrivanceLabsNewEntry) {
            metricForNewReport = selectedMetric
            showAddSheet = true
        }
    }

    private var deskHero: some View {
        LabSurfaceCard(tint: Color.white.opacity(0.08)) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Research Desk")
                        .font(.title2.weight(.bold))
                    Text(bodyCopy)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    LabStatPill(
                        title: "Active stacks",
                        value: "\(activeMetricCount)/\(NutrivanceTuningMetric.allCases.count)",
                        tint: .orange
                    )
                    LabStatPill(
                        title: "Live papers",
                        value: "\(activeReportCount)",
                        tint: .cyan
                    )
                    LabStatPill(
                        title: "Saved papers",
                        value: "\(store.reports.count)",
                        tint: .white
                    )
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(NutrivanceTuningMetric.allCases) { metric in
                        let snapshot = metricSnapshot(for: metric)
                        LabLiveValueChip(snapshot: snapshot)
                    }
                }
            }
        }
    }

    private var deskControls: some View {
        HStack(spacing: 12) {
            Button {
                store.showTestingOverlay.toggle()
            } label: {
                Label(
                    store.showTestingOverlay ? "Testing overlay on" : "Testing overlay off",
                    systemImage: store.showTestingOverlay ? "waveform.path.ecg.rectangle.fill" : "waveform.path.ecg.rectangle"
                )
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundStyle(store.showTestingOverlay ? Color.green : Color.white.opacity(0.85))
                .background(
                    Capsule()
                        .fill(store.showTestingOverlay ? Color.green.opacity(0.18) : Color.white.opacity(0.08))
                )
                .overlay(
                    Capsule()
                        .stroke(store.showTestingOverlay ? Color.green.opacity(0.32) : Color.white.opacity(0.14), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Spacer()

            Text(sortNewestFirst ? "Stacks sorted by newest paper" : "Stacks sorted by strongest live weight")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var metricDesk: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Metric Stacks")
                .font(.headline)

            MetricStackGrid(
                onToggleMetric: { metric in
                    store.setMetricGloballyEnabled(metric, enabled: !store.isMetricGloballyEnabled(metric))
                },
                onOpenMetric: { metric in
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                        selectedMetric = metric
                    }
                },
                sortedReports: sortedReports,
                snapshotFor: metricSnapshot
            )
        }
    }
    
    private func sortedReports(for metric: NutrivanceTuningMetric) -> [NutrivanceTuningReport] {
        let now = Date()
        return store.reports
            .filter { $0.metric == metric }
            .sorted {
                if sortNewestFirst {
                    return $0.createdAt > $1.createdAt
                }
                return $0.resolvedComputedWeight(asOf: now) > $1.resolvedComputedWeight(asOf: now)
            }
    }
    
    private func metricSnapshot(for metric: NutrivanceTuningMetric) -> LabsMetricSnapshot {
        let base: Double = {
            switch metric {
            case .recovery: return engine.recoveryScore
            case .strain: return engine.strainScore
            case .readiness: return engine.readinessScore
            }
        }()
        
        let result = NutrivanceTuningEngine.display(base: base, metric: metric, store: store)
        return LabsMetricSnapshot(metric: metric, base: base, adjusted: result.adjusted, delta: result.delta)
    }

    private var deskFootnote: some View {
        LabSurfaceCard(tint: Color.white.opacity(0.04)) {
            VStack(alignment: .leading, spacing: 8) {
                Text("System transparency")
                    .font(.headline)
                Text("Each paper shows how a user note becomes a bounded lab nudge. Opening a paper reveals the display-layer math, the live decay curve, and the underlying score formula side by side.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var macPendingSyncBanner: some View {
        let count = store.pendingIOSOperations.count
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "iphone.and.arrow.forward")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Waiting for iPhone or iPad")
                    .font(.subheadline.weight(.semibold))
                Text("Edits apply here immediately. \(count == 1 ? "One change is" : "\(count) changes are") queued in iCloud for your iPhone or iPad to merge into saved tuning.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.blue.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.blue.opacity(0.22), lineWidth: 1)
        )
    }

}

// MARK: - Desk + stack views

private struct MetricStackGrid: View {
    let onToggleMetric: (NutrivanceTuningMetric) -> Void
    let onOpenMetric: (NutrivanceTuningMetric) -> Void
    let sortedReports: (NutrivanceTuningMetric) -> [NutrivanceTuningReport]
    let snapshotFor: (NutrivanceTuningMetric) -> LabsMetricSnapshot
    @ObservedObject private var store = NutrivanceTuningStore.shared
    @Namespace private var labNamespace

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 280, maximum: .infinity), spacing: 16)
        ], spacing: 16) {
            ForEach(NutrivanceTuningMetric.allCases) { metric in
                MetricStackCard(
                    metric: metric,
                    reports: sortedReports(metric),
                    snapshot: snapshotFor(metric),
                    isEnabled: store.isMetricGloballyEnabled(metric),
                    namespace: labNamespace,
                    onToggleMetric: { onToggleMetric(metric) },
                    onOpenMetric: { onOpenMetric(metric) }
                )
            }
        }
    }
}

// MARK: - Metric Stack Card

private struct MetricStackCard: View {
    let metric: NutrivanceTuningMetric
    let reports: [NutrivanceTuningReport]
    let snapshot: LabsMetricSnapshot
    let isEnabled: Bool
    let namespace: Namespace.ID
    var onToggleMetric: () -> Void
    var onOpenMetric: () -> Void

    private var previewReports: [NutrivanceTuningReport] {
        Array(reports.prefix(3))
    }

    private var activeCount: Int {
        reports.filter(\.isEnabled).count
    }

    private var stackLabel: String {
        if reports.isEmpty { return "No papers yet" }
        return activeCount == 0 ? "\(reports.count) paused" : "\(activeCount) active"
    }

    @State private var isOrganized = false
    @State private var hasAppeared = false
    @State private var cardOffsets: [UUID: CGSize] = [:]

    var body: some View {
        LabSurfaceCard(tint: snapshot.accent.opacity(isEnabled ? 0.14 : 0.06)) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(metric.displayTitle, systemImage: metric.icon)
                            .font(.headline)
                            .foregroundStyle(isEnabled ? snapshot.accent : .secondary)
                        Text(stackLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: onToggleMetric) {
                        Image(systemName: isEnabled ? "checkmark.circle.fill" : "pause.circle")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(isEnabled ? snapshot.accent : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isEnabled ? "Pause \(metric.displayTitle)" : "Enable \(metric.displayTitle)")
                }

                paperPreviewArea
                    .frame(height: 132)

                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.formattedAdjusted)
                            .font(.title3.weight(.bold))
                        Text(snapshot.statusTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    LabDeltaBadge(deltaText: snapshot.deltaText, tint: snapshot.accent, emphasized: abs(snapshot.delta) > 0.01)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .onTapGesture(perform: onOpenMetric)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    isOrganized = true
                }
            }
        }
    }

    private var paperPreviewArea: some View {
        ZStack(alignment: .topLeading) {
            if previewReports.isEmpty {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.05 + (Double(index) * 0.015)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                        .rotationEffect(.degrees(Double(index) * 1.2))
                        .offset(x: CGFloat(index * 10), y: CGFloat(index * 8))
                        .frame(height: 116)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Open this stack to add a new lab paper for \(metric.displayTitle.lowercased()).")
                        .font(.subheadline.weight(.semibold))
                    Text(metric.stackSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                if isOrganized {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(previewReports.enumerated()), id: \.element.id) { index, report in
                            LabPaperPreview(
                                report: report,
                                metric: metric,
                                accent: snapshot.accent,
                                compact: true
                            )
                            .matchedGeometryEffect(id: report.id, in: namespace)
                            .frame(height: 60)
                        }
                    }
                } else {
                    ForEach(Array(previewReports.enumerated()), id: \.element.id) { index, report in
                        let rotation = Double(index) * 1.6 - 1.6
                        let offset = cardOffsets[report.id] ?? .zero
                        
                        LabPaperPreview(
                            report: report,
                            metric: metric,
                            accent: snapshot.accent,
                            compact: true
                        )
                        .matchedGeometryEffect(id: report.id, in: namespace)
                        .rotationEffect(.degrees(rotation))
                        .offset(x: CGFloat(index * 12) + offset.width, y: CGFloat(index * 9) + offset.height)
                        .zIndex(Double(previewReports.count - index))
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    cardOffsets[report.id] = value.translation
                                }
                                .onEnded { _ in
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        cardOffsets[report.id] = .zero
                                    }
                                }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Metric Stack Detail View

struct MetricStackDetailView: View {
    let metric: NutrivanceTuningMetric
    let reports: [NutrivanceTuningReport]
    let snapshot: LabsMetricSnapshot
    @ObservedObject var store: NutrivanceTuningStore
    let namespace: Namespace.ID
    var onSelectReport: (NutrivanceTuningReport) -> Void
    var onAddReport: () -> Void
    var sortNewestFirst: Bool = true
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @State private var isOrganized = false
    @State private var cardPositions: [UUID: CGPoint] = [:]
    @State private var sortByNewestFirst: Bool = true
    @State private var nextCardZOrder: Int = 1
    @State private var isDrawingMode: Bool = false
    @State private var canvasDrawing: [String: Data] = [:]
    @State private var isHeaderMinimized: Bool = false
    
    private let cardWidth: CGFloat = 300
    private let cardHeight: CGFloat = 280
    private let cardSpacing: CGFloat = 16

    private var isCompactWidth: Bool {
        horizontalSizeClass == .compact
    }

    private var sortedReports: [NutrivanceTuningReport] {
        let now = Date()
        return reports.sorted {
            if sortByNewestFirst {
                return $0.createdAt > $1.createdAt
            }
            return $0.resolvedComputedWeight(asOf: now) > $1.resolvedComputedWeight(asOf: now)
        }
    }

    private func defaultPositions(for width: CGFloat) -> [UUID: CGPoint] {
        var positions: [UUID: CGPoint] = [:]
        let cardsPerRow = max(1, Int((width + cardSpacing) / (cardWidth + cardSpacing)))
        
        let fanOverlap: CGFloat = 20
        let fanStartX: CGFloat = 20
        let fanStartY: CGFloat = 20
        
        for (index, report) in sortedReports.enumerated() {
            let row = index / cardsPerRow
            let col = index % cardsPerRow
            
            let baseX = fanStartX + CGFloat(col) * (cardWidth - fanOverlap)
            let baseY = fanStartY + CGFloat(row) * (cardHeight + 24)
            
            positions[report.id] = CGPoint(x: baseX, y: baseY)
        }
        return positions
    }

    var body: some View {
        VStack(spacing: 0) {
            headerCard
                .padding(.horizontal, isCompactWidth ? 16 : 24)
                .padding(.top, isCompactWidth ? 16 : 24)
                .padding(.bottom, 16)

            if reports.isEmpty {
                emptyState
                    .padding(.horizontal, isCompactWidth ? 16 : 24)
            } else if isCompactWidth {
                compactReportList
            } else {
                reportFanArea
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.82).ignoresSafeArea())
        .onAppear {
            sortByNewestFirst = sortNewestFirst
            cardPositions = defaultPositions(for: 800)
        }
        .onChange(of: sortByNewestFirst) { _, newValue in
            sortByNewestFirst = newValue
        }
        .onDisappear {
            isOrganized = false
            isHeaderMinimized = false
            cardPositions.removeAll()
        }
    }

    private var glassyTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var glassySecondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.6)
    }

    private var glassyStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1)
    }

    private var glassyBackgroundColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.6)
            : Color.white.opacity(0.85)
    }

    private var headerCard: some View {
        Group {
            if !isOrganized && isHeaderMinimized {
                minimizedHeader
            } else {
                fullHeader
            }
        }
    }
    
    private var minimizedHeader: some View {
        GlassmorphicCard(
            accent: snapshot.accent,
            colorScheme: colorScheme
        ) {
            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: metric.icon)
                        .foregroundStyle(snapshot.accent)
                    Text(metric.displayTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(glassyTextColor)
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    Text(snapshot.formattedAdjusted + metric.unitSuffix)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(snapshot.accent)
                    
                    Text(snapshot.deltaText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(glassySecondaryTextColor)
                    
                    Text("\(reports.count) papers")
                        .font(.caption)
                        .foregroundStyle(glassySecondaryTextColor)
                }
                
                Spacer()
                
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isHeaderMinimized = false
                    }
                } label: {
                    Image(systemName: "chevron.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(snapshot.accent)
                }
            }
        }
        .padding(.horizontal, isCompactWidth ? 16 : 24)
        .padding(.vertical, 12)
    }
    
    private var fullHeader: some View {
        GlassmorphicCard(
            accent: snapshot.accent,
            colorScheme: colorScheme
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(metric.displayTitle)
                            .font(isCompactWidth ? .title2.weight(.bold) : .title3.weight(.bold))
                            .foregroundStyle(glassyTextColor)
                        Text(metric.stackSummary)
                            .font(.subheadline)
                            .foregroundStyle(glassySecondaryTextColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    
                    if !isOrganized {
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                isHeaderMinimized = true
                            }
                        } label: {
                            Image(systemName: "chevron.down.circle.fill")
                                .font(.title2)
                                .foregroundStyle(glassySecondaryTextColor)
                        }
                    }
                }

                HStack(spacing: 10) {
                    LabStatPill(title: "Live score", value: snapshot.formattedAdjusted + metric.unitSuffix, tint: snapshot.accent)
                    LabStatPill(title: "Visible delta", value: snapshot.deltaText, tint: glassyTextColor.opacity(0.8))
                    LabStatPill(title: "Papers", value: "\(reports.count)", tint: .cyan)
                }

                HStack(spacing: 12) {
                    Button(action: onAddReport) {
                        Label("New paper", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .tint(snapshot.accent)
                    .foregroundStyle(glassyTextColor)

                    Button {
                        store.setMetricGloballyEnabled(metric, enabled: !store.isMetricGloballyEnabled(metric))
                    } label: {
                        Label(
                            store.isMetricGloballyEnabled(metric) ? "Metric live" : "Metric paused",
                            systemImage: store.isMetricGloballyEnabled(metric) ? "checkmark.circle.fill" : "pause.circle"
                        )
                    }
                    .buttonStyle(.bordered)
                    .tint(store.isMetricGloballyEnabled(metric) ? .green : .orange)
                    .foregroundStyle(glassyTextColor)

                    Menu {
                        Button {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                                sortByNewestFirst = true
                                cardPositions.removeAll()
                            }
                        } label: {
                            Label("Newest first", systemImage: sortByNewestFirst ? "checkmark" : "")
                        }
                        Button {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                                sortByNewestFirst = false
                                cardPositions.removeAll()
                            }
                        } label: {
                            Label("Strongest first", systemImage: !sortByNewestFirst ? "checkmark" : "")
                        }
                    } label: {
                        Label("Arrange by", systemImage: "arrow.up.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .tint(snapshot.accent)
                    .foregroundStyle(glassyTextColor)
                }
            }
        }
    }

    private var emptyState: some View {
        GlassmorphicCard(
            accent: snapshot.accent,
            colorScheme: colorScheme
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("No papers in this stack")
                    .font(.headline)
                    .foregroundStyle(glassyTextColor)
                Text("Start with a short note about what feels under- or over-weighted in \(metric.displayTitle.lowercased()). The report sheet will translate it into live display math and a transparent formula readout.")
                    .font(.subheadline)
                    .foregroundStyle(glassySecondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onAddReport) {
                    Label("Create first paper", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(snapshot.accent)
                .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var compactReportList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(Array(reports.enumerated()), id: \.element.id) { index, report in
                    Button {
                        onSelectReport(report)
                    } label: {
                        MetricStackReportCardCompact(
                            report: report,
                            metric: metric,
                            accent: snapshot.accent,
                            colorScheme: colorScheme
                        )
                        .matchedGeometryEffect(id: report.id, in: namespace)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private var reportFanArea: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Tap a paper to open the full lab report.")
                    .font(.subheadline)
                    .foregroundStyle(glassySecondaryTextColor)
                
                Spacer()
                
                Button {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                        isOrganized.toggle()
                        if isOrganized {
                            isHeaderMinimized = false
                            cardPositions.removeAll()
                        }
                    }
                } label: {
                    Label(
                        isOrganized ? "Freeform" : "Organize",
                        systemImage: isOrganized ? "rectangle.grid.1x2" : "rectangle.stack"
                    )
                    .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(snapshot.accent)
                
                if !isOrganized {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isDrawingMode.toggle()
                        }
                    } label: {
                        Image(systemName: isDrawingMode ? "pencil.circle.fill" : "pencil.circle")
                    }
                    .buttonStyle(.bordered)
                    .tint(isDrawingMode ? .blue : snapshot.accent)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)

            if isOrganized {
                if sortedReports.count <= 3 {
                    HStack(spacing: 16) {
                        ForEach(Array(sortedReports.enumerated()), id: \.element.id) { index, report in
                            Button {
                                onSelectReport(report)
                            } label: {
                                MetricStackReportCard(
                                    report: report,
                                    metric: metric,
                                    accent: snapshot.accent,
                                    colorScheme: colorScheme,
                                    cardWidth: nil
                                )
                                .matchedGeometryEffect(id: report.id, in: namespace)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16)
                        ], spacing: 16) {
                            ForEach(Array(sortedReports.enumerated()), id: \.element.id) { index, report in
                                Button {
                                    onSelectReport(report)
                                } label: {
                                    MetricStackReportCard(
                                        report: report,
                                        metric: metric,
                                        accent: snapshot.accent,
                                        colorScheme: colorScheme,
                                        cardWidth: nil
                                    )
                                    .matchedGeometryEffect(id: report.id, in: namespace)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
            } else {
                freeformCanvas
            }
        }
        .padding(.bottom, 24)
    }

    private var freeformCanvas: some View {
        let canvasWidth: CGFloat = 3000
        let canvasHeight: CGFloat = 2000
        
        return ScrollView([.horizontal, .vertical], showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                InfiniteGridView()
                    .frame(width: canvasWidth, height: canvasHeight)
                    .allowsHitTesting(false)
                
                if isDrawingMode {
                    PencilKitCanvasView(
                        drawingData: Binding(
                            get: { canvasDrawing[metric.rawValue] },
                            set: { canvasDrawing[metric.rawValue] = $0 }
                        ),
                        isDrawingMode: $isDrawingMode
                    )
                    .frame(width: canvasWidth, height: canvasHeight)
                }
                
                ForEach(Array(sortedReports.enumerated()), id: \.element.id) { index, report in
                    let rotation = Double(index) * 2 - Double(sortedReports.count - 1)
                    
                    DraggableLabPaperCard(
                        report: report,
                        metric: metric,
                        accent: snapshot.accent,
                        colorScheme: colorScheme,
                        cardWidth: cardWidth,
                        rotation: rotation,
                        position: cardPositions[report.id] ?? .zero,
                        onTap: {
                            if !isDrawingMode {
                                onSelectReport(report)
                            }
                        },
                        onDragEnded: { newPosition in
                            cardPositions[report.id] = newPosition
                        },
                        onDragStart: {
                            bringCardToFront(report.id)
                        }
                    )
                    .zIndex(Double(index))
                }
            }
            .frame(width: canvasWidth, height: canvasHeight)
        }
        .background(Color.black.opacity(0.3))
    }

    private func bringCardToFront(_ id: UUID) {
        nextCardZOrder += 1
    }
}

struct InfiniteGridView: View {
    let gridSpacing: CGFloat = 50
    let dotRadius: CGFloat = 2.0
    
    var body: some View {
        Canvas { context, size in
            for x in stride(from: CGFloat(0), through: size.width, by: gridSpacing) {
                for y in stride(from: CGFloat(0), through: size.height, by: gridSpacing) {
                    context.fill(
                        Circle().path(in: CGRect(
                            x: x - dotRadius,
                            y: y - dotRadius,
                            width: dotRadius * 2,
                            height: dotRadius * 2
                        )),
                        with: .color(Color.gray.opacity(0.25))
                    )
                }
            }
        }
    }
}

import PencilKit

struct PencilKitCanvasView: UIViewRepresentable {
    @Binding var drawingData: Data?
    @Binding var isDrawingMode: Bool
    
    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        canvas.delegate = context.coordinator
        
        if let data = drawingData,
           let drawing = try? PKDrawing(data: data) {
            canvas.drawing = drawing
        }
        
        context.coordinator.setupToolPicker(for: canvas)
        
        return canvas
    }
    
    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if let data = drawingData {
            if canvas.drawing.dataRepresentation() != data {
                if let drawing = try? PKDrawing(data: data) {
                    canvas.drawing = drawing
                }
            }
        }
        
        if isDrawingMode {
            context.coordinator.toolPicker?.setVisible(true, forFirstResponder: canvas)
            canvas.becomeFirstResponder()
        } else {
            context.coordinator.toolPicker?.setVisible(false, forFirstResponder: canvas)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilKitCanvasView
        var toolPicker: PKToolPicker?
        
        init(_ parent: PencilKitCanvasView) {
            self.parent = parent
            super.init()
        }
        
        func setupToolPicker(for canvas: PKCanvasView) {
            if let window = UIApplication.shared.windows.first {
                toolPicker = PKToolPicker.shared(for: window)
                toolPicker?.addObserver(canvas)
                toolPicker?.setVisible(true, forFirstResponder: canvas)
                canvas.becomeFirstResponder()
            }
        }
        
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawingData = canvasView.drawing.dataRepresentation()
        }
    }
}

private struct DraggableLabPaperCard: View {
    let report: NutrivanceTuningReport
    let metric: NutrivanceTuningMetric
    let accent: Color
    let colorScheme: ColorScheme
    let cardWidth: CGFloat
    let rotation: Double
    var position: CGPoint
    var onTap: () -> Void
    var onDragEnded: (CGPoint) -> Void
    var onDragStart: () -> Void

    @GestureState private var dragTranslation: CGSize = .zero
    @State private var isDragging: Bool = false

    private var effectiveRotation: Double {
        isDragging ? 0 : rotation
    }

    private var effectiveScale: CGFloat {
        isDragging ? 1.08 : 1.0
    }

    private var resolvedPosition: CGPoint {
        CGPoint(
            x: position.x + dragTranslation.width,
            y: position.y + dragTranslation.height
        )
    }

    var body: some View {
        MetricStackReportCardContent(
            report: report,
            metric: metric,
            accent: accent,
            colorScheme: colorScheme,
            cardWidth: cardWidth
        )
        .rotationEffect(.degrees(effectiveRotation))
        .scaleEffect(effectiveScale)
        .shadow(
            color: Color.black.opacity(isDragging ? 0.4 : 0.2),
            radius: isDragging ? 20 : 10,
            x: 0,
            y: isDragging ? 15 : 5
        )
        .position(
            x: resolvedPosition.x + cardWidth / 2,
            y: resolvedPosition.y + 140
        )
        .gesture(
            DragGesture()
                .onChanged { _ in
                    if !isDragging {
                        isDragging = true
                        onDragStart()
                    }
                }
                .updating($dragTranslation) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    let newPosition = CGPoint(
                        x: position.x + value.translation.width,
                        y: position.y + value.translation.height
                    )
                    onDragEnded(newPosition)
                    isDragging = false
                }
        )
        .onTapGesture {
            if !isDragging {
                onTap()
            }
        }
    }
}

private struct MetricStackReportCardContent: View {
    let report: NutrivanceTuningReport
    let metric: NutrivanceTuningMetric
    let accent: Color
    let colorScheme: ColorScheme
    let cardWidth: CGFloat

    var body: some View {
        LabPaperPreview(
            report: report,
            metric: metric,
            accent: accent,
            compact: false,
            colorScheme: colorScheme,
            showFooter: true,
            showWeightBar: true,
            weightBarValue: report.resolvedComputedWeight()
        )
        .frame(width: cardWidth, height: cardHeight)
    }

    private var cardHeight: CGFloat {
        280
    }
}

private struct MetricStackReportCard: View {
    let report: NutrivanceTuningReport
    let metric: NutrivanceTuningMetric
    let accent: Color
    var colorScheme: ColorScheme = .dark
    var cardWidth: CGFloat? = 300

    var body: some View {
        LabPaperPreview(
            report: report,
            metric: metric,
            accent: accent,
            compact: false,
            colorScheme: colorScheme,
            showFooter: true,
            showWeightBar: true,
            weightBarValue: report.resolvedComputedWeight()
        )
        .frame(minWidth: cardWidth ?? 280, maxWidth: .infinity, minHeight: cardHeight, maxHeight: .infinity)
        .fixedSize(horizontal: cardWidth != nil, vertical: false)
    }

    private var cardHeight: CGFloat {
        280
    }
}

private struct MetricStackReportCardCompact: View {
    let report: NutrivanceTuningReport
    let metric: NutrivanceTuningMetric
    let accent: Color
    var colorScheme: ColorScheme = .dark

    private var textColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.55)
    }

    private var cardBackgroundColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.5)
            : Color.white.opacity(0.9)
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(report.factor.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(textColor)
                    Spacer()
                    Image(systemName: report.isEnabled ? "checkmark.circle.fill" : "pause.circle.fill")
                        .foregroundStyle(report.isEnabled ? accent : secondaryTextColor)
                }

                Text(report.userNote)
                    .font(.subheadline)
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack {
                    Text(report.shortAttributionLabel)
                        .font(.caption)
                        .foregroundStyle(secondaryTextColor)
                    Spacer()
                    Text(report.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(secondaryTextColor)
                }
            }

            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "%.0f%%", report.resolvedComputedWeight() * 100))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(accent)
                Text("weight")
                    .font(.caption2)
                    .foregroundStyle(secondaryTextColor)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(accent.opacity(0.08))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(glassyStrokeColor, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 8, y: 4)
    }

    private var glassyStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }
}

private struct LabPaperPreview: View {
    let report: NutrivanceTuningReport
    let metric: NutrivanceTuningMetric
    let accent: Color
    let compact: Bool
    var colorScheme: ColorScheme = .dark
    var showFooter: Bool = true
    var showWeightBar: Bool = false
    var weightBarValue: Double = 0
    var backgroundOpacity: Double? = nil

    private var textColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.55)
    }

    private var cardBackgroundColor: Color {
        let opacity = backgroundOpacity ?? (colorScheme == .dark ? 0.55 : 0.92)
        return colorScheme == .dark
            ? Color.black.opacity(opacity)
            : Color.white.opacity(opacity)
    }

    private var strokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack(alignment: .top) {
                Text(report.factor.displayTitle)
                    .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(textColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(accent.opacity(0.2))
                    )
                Spacer()
                Image(systemName: report.isEnabled ? "checkmark.circle.fill" : "pause.circle.fill")
                    .foregroundStyle(report.isEnabled ? accent : secondaryTextColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("\(report.factor.displayTitle) -> \(metric.displayTitle)")
                    .font(compact ? .subheadline.weight(.semibold) : .headline)
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                Text(report.userNote)
                    .font(compact ? .caption : .subheadline)
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(compact ? 3 : 4)
                    .multilineTextAlignment(.leading)
            }

            Spacer()

            if showFooter {
                VStack(alignment: .leading, spacing: 8) {
                    if showWeightBar {
                        LabWeightBar(value: weightBarValue, tint: accent)
                        HStack {
                            Text("Live \(String(format: "%.0f%%", weightBarValue * 100))")
                            Spacer()
                            Text("Base \(String(format: "%.0f%%", report.effectiveStrength * 100))")
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(secondaryTextColor)
                    }

                    if compact {
                        Text(report.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundStyle(secondaryTextColor)
                    } else {
                        HStack {
                            Text(report.shortAttributionLabel)
                                .lineLimit(1)
                                .foregroundStyle(secondaryTextColor)
                            Spacer()
                            Text(report.createdAt.formatted(date: .abbreviated, time: .omitted))
                                .foregroundStyle(secondaryTextColor)
                        }
                        .font(.caption2)
                    }
                }
            }
        }
        .padding(compact ? 14 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: compact ? 20 : 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [cardBackgroundColor, accent.opacity(colorScheme == .dark ? 0.12 : 0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 20 : 24, style: .continuous)
                .stroke(strokeColor, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 16, y: 10)
    }
}

// MARK: - Report detail sheet

private struct TuningReportDetailView: View {
    @ObservedObject private var store = NutrivanceTuningStore.shared
    @ObservedObject private var engine = HealthStateEngine.shared
    @Environment(\.dismiss) private var dismiss

    let reportID: UUID

    @State private var showEditor = false

    private var liveReport: NutrivanceTuningReport? {
        store.reports.first(where: { $0.id == reportID })
    }

    private var context: TuningReportLabContext? {
        liveReport.map { TuningReportLabContext(report: $0, store: store, engine: engine) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let report = liveReport, let context {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            reportHeader(report: report, context: context)
                            appliedNudgeSection(report: report, context: context)
                            interpretationSection(report: report, context: context)
                            decaySection(report: report, context: context)
                            appliedDisplayFormulaSection(report: report, context: context)
                            metricFormulaSection(report: report, context: context)
                            effectPreviewSection(report: report, context: context)
                        }
                        .padding()
                        .padding(.bottom, 28)
                    }
                    .background(GradientBackgrounds().programBuilderMeshBackground().ignoresSafeArea())
                } else {
                    ContentUnavailableView(
                        "Report unavailable",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("This paper may have been deleted or moved from another device.")
                    )
                    .padding()
                }
            }
            .navigationTitle("Lab Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }

                if let report = liveReport {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button("Edit report") {
                                showEditor = true
                            }
                            Button(report.isEnabled ? "Disable report" : "Enable report") {
                                var updated = report
                                updated.isEnabled.toggle()
                                store.updateReport(updated)
                            }
                            Button(role: .destructive) {
                                store.deleteReport(id: report.id)
                                dismiss()
                            } label: {
                                Label("Delete report", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            if let report = liveReport {
                NutrivanceTuningReportEditorSheet(
                    existing: report,
                    seedMetric: report.metric,
                    onSave: { updated in
                        store.updateReport(updated)
                        showEditor = false
                    },
                    onCancel: {
                        showEditor = false
                    }
                )
            }
        }
    }

    private func reportHeader(report: NutrivanceTuningReport, context: TuningReportLabContext) -> some View {
        LabSurfaceCard(tint: context.snapshot.accent.opacity(0.15)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(report.factor.displayTitle) -> \(report.metric.displayTitle)")
                            .font(.title3.weight(.bold))
                        Text(report.userNote)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: report.userDirection >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .font(.title.weight(.semibold))
                        .foregroundStyle(report.userDirection >= 0 ? Color.green : Color.orange)
                }

                HStack(spacing: 10) {
                    LabStatPill(title: "Metric", value: report.metric.displayTitle, tint: context.snapshot.accent)
                    LabStatPill(title: "Factor", value: report.factor.displayTitle, tint: .white)
                    LabStatPill(title: "Created", value: report.createdAt.formatted(date: .abbreviated, time: .omitted), tint: .cyan)
                }
            }
        }
    }

    private func appliedNudgeSection(report: NutrivanceTuningReport, context: TuningReportLabContext) -> some View {
        LabSurfaceCard(tint: Color.white.opacity(0.06)) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Applied Nudge")
                    .font(.headline)

                HStack(spacing: 10) {
                    LabStatPill(title: "Direction", value: report.userDirection >= 0 ? "Increase \(report.metric.displayTitle)" : "Decrease \(report.metric.displayTitle)", tint: report.userDirection >= 0 ? .green : .orange)
                    LabStatPill(title: "Profile", value: report.nudgeLevel.label, tint: context.snapshot.accent)
                    LabStatPill(title: "Enabled", value: report.isEnabled ? "Yes" : "No", tint: report.isEnabled ? .cyan : Color.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Base strength")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(context.baseStrengthText)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { report.effectiveStrength },
                            set: { store.setEffectiveStrength(id: report.id, strength: $0) }
                        ),
                        in: 0...1
                    )
                    .tint(context.snapshot.accent)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Live weight")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(context.liveWeightText)
                            .font(.title3.weight(.bold))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Display delta")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(context.reportDeltaText)
                            .font(.title3.weight(.bold))
                    }

                    Spacer()

                    Toggle(
                        "Enabled",
                        isOn: Binding(
                            get: { report.isEnabled },
                            set: { isOn in
                                var updated = report
                                updated.isEnabled = isOn
                                store.updateReport(updated)
                            }
                        )
                    )
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }
        }
    }

    private func interpretationSection(report: NutrivanceTuningReport, context: TuningReportLabContext) -> some View {
        LabSurfaceCard(tint: context.snapshot.accent.opacity(0.08)) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Model Interpretation")
                    .font(.headline)
                Text(labInterpretation(for: report, context: context))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func decaySection(report: NutrivanceTuningReport, context: TuningReportLabContext) -> some View {
        LabSurfaceCard(tint: Color.white.opacity(0.05)) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Decay Function")
                    .font(.headline)

                LabDecayCurve(weight: context.liveWeight, decayRate: report.decayRate, accent: context.snapshot.accent)
                    .frame(height: 92)

                Text("w(t) = w0 x e^(-lambda * t)")
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    LabStatPill(title: "Current weight", value: context.liveWeightText, tint: context.snapshot.accent)
                    LabStatPill(title: "Lambda / day", value: String(format: "%.4f", report.decayRate), tint: .white)
                    LabStatPill(title: "Age", value: context.ageText, tint: .cyan)
                }

                Text("The paper fades from its base strength toward zero over time. Touching the slider or editing the report refreshes the live-weight anchor so the nudge can stay intentional instead of permanent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func appliedDisplayFormulaSection(report: NutrivanceTuningReport, context: TuningReportLabContext) -> some View {
        LabSurfaceCard(tint: Color.white.opacity(0.05)) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Applied Display Formula")
                    .font(.headline)

                Text("Displayed \(report.metric.displayTitle) = Base \(report.metric.displayTitle) + sum(delta_i)")
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("delta_report = direction x nudge scalar x live weight x (max delta / 3)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text(context.appliedFormulaLine)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    LabStatPill(title: "Base strength", value: context.baseStrengthText, tint: .white)
                    LabStatPill(title: "Live weight", value: context.liveWeightText, tint: context.snapshot.accent)
                    LabStatPill(title: "Contribution", value: context.reportDeltaText, tint: context.snapshot.accent)
                }

                Text("This paper does not rewrite raw HealthKit inputs. It contributes a bounded display-layer delta after the underlying score is computed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func metricFormulaSection(report: NutrivanceTuningReport, context: TuningReportLabContext) -> some View {
        let formula = metricFormulaDescriptor(for: report, context: context)

        return LabSurfaceCard(tint: context.snapshot.accent.opacity(0.08)) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Metric Formula")
                    .font(.headline)
                Text(formula.equation)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(formula.rows) { row in
                    LabFormulaRow(row: row, accent: context.snapshot.accent)
                }
            }
        }
    }

    private func effectPreviewSection(report: NutrivanceTuningReport, context: TuningReportLabContext) -> some View {
        LabSurfaceCard(tint: Color.white.opacity(0.06)) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Effect Preview")
                    .font(.headline)

                HStack(spacing: 12) {
                    LabPreviewMetricCard(
                        title: "Without this paper",
                        value: context.withoutReportText + report.metric.unitSuffix,
                        detail: report.metric.previewLabel(for: context.withoutReport.adjusted),
                        tint: .white
                    )
                    LabPreviewMetricCard(
                        title: "With this paper",
                        value: context.withReportText + report.metric.unitSuffix,
                        detail: report.metric.previewLabel(for: context.withReport.adjusted),
                        tint: context.snapshot.accent
                    )
                    LabPreviewMetricCard(
                        title: "Delta",
                        value: context.previewDeltaText,
                        detail: report.isEnabled && context.metricEnabled ? "Live contribution" : "Currently neutral",
                        tint: context.snapshot.accent
                    )
                }

                if !context.metricEnabled {
                    Text("\(report.metric.displayTitle) is globally paused, so this paper is saved but currently has no visible effect.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !report.isEnabled {
                    Text("This paper is currently disabled, so the with/without preview collapses to the same visible score until it is re-enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("The preview compares the current live score with this one paper removed versus re-applied, while leaving every other paper in the stack unchanged.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Editor

private struct NutrivanceTuningReportEditorSheet: View {
    let existing: NutrivanceTuningReport?
    let seedMetric: NutrivanceTuningMetric?
    var onSave: (NutrivanceTuningReport) -> Void
    var onCancel: () -> Void

    @State private var metric: NutrivanceTuningMetric = .recovery
    @State private var factor: NutrivanceTuningFactor = .sleep
    @State private var directionUp = true
    @State private var nudge: NutrivanceTuningNudgeLevel = .medium
    @State private var note = ""
    @State private var shortLabel = ""

    private var availableFactors: [NutrivanceTuningFactor] {
        metric.availableFactors
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Metric") {
                    Picker("Metric", selection: $metric) {
                        ForEach(NutrivanceTuningMetric.allCases) { metric in
                            Text(metric.displayTitle).tag(metric)
                        }
                    }
                    Picker("Factor", selection: $factor) {
                        ForEach(availableFactors) { factor in
                            Text(factor.displayTitle).tag(factor)
                        }
                    }
                }

                Section("Nudge") {
                    Toggle("Direction: nudge score up", isOn: $directionUp)
                    Picker("Strength", selection: $nudge) {
                        ForEach(NutrivanceTuningNudgeLevel.allCases, id: \.self) { level in
                            Text(level.label).tag(level)
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
                        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedNote.isEmpty else { return }

                        let label = shortLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "\(factor.displayTitle) tuning"
                            : shortLabel.trimmingCharacters(in: .whitespacesAndNewlines)

                        let report = NutrivanceTuningReport(
                            id: existing?.id ?? UUID(),
                            createdAt: existing?.createdAt ?? Date(),
                            metric: metric,
                            factor: factor,
                            userDirection: directionUp ? 1 : -1,
                            nudgeLevel: nudge,
                            userNote: trimmedNote,
                            shortAttributionLabel: label,
                            effectiveStrength: existing?.effectiveStrength ?? 0.55,
                            decayRate: existing?.decayRate ?? NutrivanceTuningReport.defaultDecayRate,
                            lastAppliedAt: existing?.lastAppliedAt ?? Date(),
                            computedWeight: existing?.computedWeight,
                            isEnabled: existing?.isEnabled ?? true
                        )
                        onSave(report)
                    }
                    .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: metric) { _, newMetric in
                if !newMetric.availableFactors.contains(factor) {
                    factor = newMetric.availableFactors.first ?? .composite
                }
            }
            .onAppear {
                if let existing {
                    metric = existing.metric
                    factor = existing.metric.availableFactors.contains(existing.factor)
                        ? existing.factor
                        : existing.metric.availableFactors.first ?? .composite
                    directionUp = existing.userDirection >= 0
                    nudge = existing.nudgeLevel
                    note = existing.userNote
                    shortLabel = existing.shortAttributionLabel
                } else if let seedMetric {
                    metric = seedMetric
                    factor = seedMetric.availableFactors.first ?? .composite
                }
            }
        }
    }
}

// MARK: - Lab analysis models

struct LabsMetricSnapshot {
    let metric: NutrivanceTuningMetric
    let base: Double
    let adjusted: Double
    let delta: Double

    var accent: Color { metric.accentColor }
    var formattedAdjusted: String { metric.formatValue(adjusted) }
    var deltaText: String { metric.signedDeltaText(delta) }

    var statusTitle: String {
        metric.previewLabel(for: adjusted)
    }
}

@MainActor
private struct TuningReportLabContext {
    let report: NutrivanceTuningReport
    let snapshot: LabsMetricSnapshot
    let withReport: NutrivanceTuningDisplayResult
    let withoutReport: NutrivanceTuningDisplayResult
    let liveWeight: Double
    let reportDelta: Double
    let maxDelta: Double
    let metricEnabled: Bool
    let recoveryInputs: HealthStateEngine.ProRecoveryInputs
    let strainSnapshot: HealthStateEngine.StrainDebugSnapshot
    let normalizedStrain: Double
    let recoveryValue: Double
    let hrvTrendValue: Double
    let now: Date

    init(report: NutrivanceTuningReport, store: NutrivanceTuningStore, engine: HealthStateEngine, now: Date = Date()) {
        self.report = report
        self.now = now
        self.recoveryValue = engine.recoveryScore
        self.hrvTrendValue = engine.hrvTrendScore

        let baseValue: Double = {
            switch report.metric {
            case .recovery: return engine.recoveryScore
            case .strain: return engine.strainScore
            case .readiness: return engine.readinessScore
            }
        }()

        let metricEnabled = store.isMetricGloballyEnabled(report.metric)
        let reports = store.reports
        let withReport = NutrivanceTuningEngine.display(
            base: baseValue,
            metric: report.metric,
            reports: reports,
            isMetricEnabled: metricEnabled,
            asOf: now
        )
        let withoutReport = NutrivanceTuningEngine.display(
            base: baseValue,
            metric: report.metric,
            reports: reports.filter { $0.id != report.id },
            isMetricEnabled: metricEnabled,
            asOf: now
        )

        self.snapshot = LabsMetricSnapshot(metric: report.metric, base: baseValue, adjusted: withReport.adjusted, delta: withReport.delta)
        self.withReport = withReport
        self.withoutReport = withoutReport
        self.liveWeight = report.resolvedComputedWeight(asOf: now)
        self.reportDelta = withReport.adjusted - withoutReport.adjusted
        self.maxDelta = NutrivanceTuningEngine.maximumDelta(for: report.metric)
        self.metricEnabled = metricEnabled
        self.recoveryInputs = labsRecoveryInputs(engine: engine, on: now)
        self.strainSnapshot = HealthStateEngine.debugStrainSnapshot(
            label: "Live",
            acuteLoad: engine.acuteTrainingLoad,
            chronicLoad: engine.chronicTrainingLoad
        )
        self.normalizedStrain = HealthStateEngine.normalizedStrainPercent(from: engine.strainScore)
    }

    var ageText: String {
        let days = report.ageInDays(asOf: now)
        if days < 1 {
            let hours = max(1, Int((days * 24).rounded()))
            return "\(hours)h"
        }
        return "\(Int(days.rounded()))d"
    }

    var liveWeightText: String {
        String(format: "%.2f", liveWeight)
    }

    var baseStrengthText: String {
        String(format: "%.2f", report.effectiveStrength)
    }

    var reportDeltaText: String {
        report.metric.signedDeltaText(reportDelta)
    }

    var withReportText: String {
        report.metric.formatValue(withReport.adjusted)
    }

    var withoutReportText: String {
        report.metric.formatValue(withoutReport.adjusted)
    }

    var previewDeltaText: String {
        report.metric.signedDeltaText(reportDelta)
    }

    var appliedFormulaLine: String {
        let direction = report.userDirection >= 0 ? 1.0 : -1.0
        let scalar = report.nudgeLevel.scalar
        let displayScale = maxDelta / 3.0
        return String(
            format: "delta = %.0f x %.2f x %.2f x %.2f = %@",
            direction,
            scalar,
            liveWeight,
            displayScale,
            report.metric.signedDeltaText(reportDelta)
        )
    }
}

private struct LabFormulaDescriptor {
    let equation: String
    let rows: [LabFormulaRowModel]
}

private struct LabFormulaRowModel: Identifiable {
    let id = UUID()
    let title: String
    let formula: String
    let value: String
    let detail: String
    let isHighlighted: Bool
}

// MARK: - Shared lab UI

private struct GlassmorphicCard<Content: View>: View {
    let accent: Color
    let colorScheme: ColorScheme
    @ViewBuilder var content: Content

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.55)
            : Color.white.opacity(0.88)
    }

    private var strokeColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.08)
    }

    var body: some View {
        content
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(accent.opacity(colorScheme == .dark ? 0.12 : 0.06))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 16, y: 8)
    }
}

private struct LabSurfaceCard<Content: View>: View {
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(tint)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 18, y: 10)
    }
}

private struct LabStatPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.26), lineWidth: 1)
        )
    }
}

private struct LabLiveValueChip: View {
    let snapshot: LabsMetricSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(snapshot.metric.displayTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(snapshot.formattedAdjusted + snapshot.metric.unitSuffix)
                .font(.title3.weight(.bold))
            Text(snapshot.deltaText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(snapshot.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(snapshot.accent.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(snapshot.accent.opacity(0.20), lineWidth: 1)
        )
    }
}

private struct LabDeltaBadge: View {
    let deltaText: String
    let tint: Color
    let emphasized: Bool

    var body: some View {
        Text(deltaText)
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(emphasized ? tint : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(emphasized ? tint.opacity(0.14) : Color.white.opacity(0.08))
            )
    }
}

private struct LabWeightBar: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.black.opacity(0.08))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.55), tint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * max(0, min(1, value)))
            }
        }
        .frame(height: 8)
    }
}

private struct LabFormulaRow: View {
    let row: LabFormulaRowModel
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(row.value)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(row.formula)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Text(row.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(row.isHighlighted ? accent.opacity(0.12) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(row.isHighlighted ? accent.opacity(0.32) : Color.white.opacity(0.08), lineWidth: 1)
        )
        .opacity(row.isHighlighted ? 1 : 0.78)
    }
}

private struct LabPreviewMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tint.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.24), lineWidth: 1)
        )
    }
}

private struct LabDecayCurve: View {
    let weight: Double
    let decayRate: Double
    let accent: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.06))

                Path { path in
                    let width = geometry.size.width
                    let height = geometry.size.height
                    for step in 0...60 {
                        let t = Double(step) / 60.0
                        let x = width * t
                        let projectedAge = t * 30.0
                        let yValue = Foundation.exp(-decayRate * projectedAge)
                        let y = height - (height * CGFloat(yValue))
                        if step == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(
                    LinearGradient(colors: [accent.opacity(0.4), accent], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )

                Circle()
                    .fill(accent)
                    .frame(width: 12, height: 12)
                    .offset(x: geometry.size.width * max(0, min(1, CGFloat(weight))), y: geometry.size.height * 0.18)
            }
        }
    }
}

// MARK: - Formula + interpretation helpers

@MainActor
private func labsRecoveryInputs(engine: HealthStateEngine, on date: Date) -> HealthStateEngine.ProRecoveryInputs {
    let normalizedDay = Calendar.current.startOfDay(for: date)
    return HealthStateEngine.proRecoveryInputs(
        latestHRV: HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.effectHRV)
            ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.nightlyAnchoredHRV)
            ?? engine.readinessEffectHRV
            ?? engine.readinessHRV
            ?? engine.latestHRV,
        restingHeartRate: HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.basalSleepingHeartRate)
            ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.dailyRestingHeartRate)
            ?? engine.readinessBasalHeartRate
            ?? engine.restingHeartRate,
        sleepDurationHours: HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.anchoredSleepDuration)
            ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.dailySleepDuration)
            ?? engine.readinessSleepDuration
            ?? engine.sleepHours,
        timeInBedHours: HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.anchoredTimeInBed)
            ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.anchoredSleepDuration)
            ?? HealthStateEngine.smoothedValue(for: normalizedDay, values: engine.dailySleepDuration)
            ?? engine.readinessTimeInBed
            ?? engine.sleepHours,
        hrvBaseline60Day: engine.hrvBaseline60Day,
        rhrBaseline60Day: engine.rhrBaseline60Day,
        sleepBaseline60Day: engine.sleepBaseline60Day,
        hrvBaseline7Day: engine.hrvBaseline7Day,
        rhrBaseline7Day: engine.rhrBaseline7Day,
        sleepBaseline7Day: engine.sleepBaseline7Day,
        bedtimeVarianceMinutes: HealthStateEngine.circularStandardDeviationMinutes(from: engine.sleepStartHours, around: normalizedDay)
    )
}

@MainActor
private func labInterpretation(for report: NutrivanceTuningReport, context: TuningReportLabContext) -> String {
    if !context.metricEnabled {
        return "\(report.metric.displayTitle) is globally paused right now, so this paper is stored as intent but not actively changing the visible score."
    }

    if !report.isEnabled {
        return "This paper is saved but currently disabled. Re-enabling it will let the lab layer bias the visible \(report.metric.displayTitle.lowercased()) score \(report.userDirection >= 0 ? "upward" : "downward") again."
    }

    let emphasis: String = {
        switch report.factor {
        case .sleep:
            return "sleep should matter \(report.userDirection >= 0 ? "more" : "less") in the current read"
        case .hrv:
            return "HRV should pull \(report.metric.displayTitle.lowercased()) \(report.userDirection >= 0 ? "up" : "down") more aggressively"
        case .rhr:
            return "resting heart rate should carry a \(report.userDirection >= 0 ? "lighter" : "heavier") cost"
        case .strainLoad:
            return "recent load should feel \(report.userDirection >= 0 ? "less punishing" : "more punishing") in the score"
        case .readinessBlend:
            return "the readiness blend should lean \(report.userDirection >= 0 ? "more optimistic" : "more conservative")"
        case .composite:
            return "the overall blend should lean \(report.userDirection >= 0 ? "higher" : "lower")"
        }
    }()

    return "Your note implies \(emphasis). The underlying engine stays unchanged, while this paper adds a bounded lab delta of about \(context.reportDeltaText) to the visible \(report.metric.displayTitle.lowercased()) score."
}

@MainActor
private func metricFormulaDescriptor(for report: NutrivanceTuningReport, context: TuningReportLabContext) -> LabFormulaDescriptor {
    switch report.metric {
    case .recovery:
        return recoveryFormulaDescriptor(report: report, context: context)
    case .strain:
        return strainFormulaDescriptor(report: report, context: context)
    case .readiness:
        return readinessFormulaDescriptor(report: report, context: context)
    }
}

@MainActor
private func recoveryFormulaDescriptor(report: NutrivanceTuningReport, context: TuningReportLabContext) -> LabFormulaDescriptor {
    let inputs = context.recoveryInputs
    let highlightSleep = report.factor == .sleep
    let highlightHRV = report.factor == .hrv
    let highlightRHR = report.factor == .rhr
    let highlightBlend = report.factor == .composite

    return LabFormulaDescriptor(
        equation: "Recovery = min(((sigma((0.85 x HRV_z) - (0.25 x RHR_penalty_z) + 1.6) x 100) - circadian) x sleepScalar, efficiencyCap)",
        rows: [
            LabFormulaRowModel(
                title: "Effect HRV term",
                formula: "0.85 x HRV_z",
                value: String(format: "%.2f", (inputs.hrvZScore ?? 0) * 0.85),
                detail: "Current HRV z-score: \(labOptional(inputs.hrvZScore, digits: 2)).",
                isHighlighted: highlightHRV || highlightBlend
            ),
            LabFormulaRowModel(
                title: "RHR penalty term",
                formula: "-0.25 x RHR_penalty_z",
                value: String(format: "%.2f", -((inputs.restingHeartRatePenaltyZScore ?? 0) * 0.25)),
                detail: "Higher overnight HR carries a subtractive cost when it rises above baseline.",
                isHighlighted: highlightRHR || highlightBlend
            ),
            LabFormulaRowModel(
                title: "Sleep gate",
                formula: "sleepScalar = 0.85 + (0.15 x sleepRatio)",
                value: labOptional(inputs.sleepScalar, digits: 2),
                detail: "Sleep ratio today: \(labOptional(inputs.sleepRatio, digits: 2)); goal \(String(format: "%.1f", inputs.sleepGoalHours)) h.",
                isHighlighted: highlightSleep || highlightBlend
            ),
            LabFormulaRowModel(
                title: "Circadian penalty",
                formula: "penalty = max((bedtimeVariance - 90) x 0.1, 0)",
                value: String(format: "%.1f", inputs.circadianPenalty),
                detail: "Bedtime variance only starts costing recovery after about 90 minutes of drift.",
                isHighlighted: highlightSleep
            ),
            LabFormulaRowModel(
                title: "Efficiency cap",
                formula: "if sleepEfficiency < 0.85, cap at 70",
                value: inputs.efficiencyCap.map { String(format: "%.0f", $0) } ?? "inactive",
                detail: "Sleep efficiency today: \(labOptional(inputs.sleepEfficiency.map { $0 * 100 }, digits: 0))%.",
                isHighlighted: false
            )
        ]
    )
}

@MainActor
private func strainFormulaDescriptor(report: NutrivanceTuningReport, context: TuningReportLabContext) -> LabFormulaDescriptor {
    let snapshot = context.strainSnapshot
    let highlightLoad = report.factor == .strainLoad || report.factor == .composite

    return LabFormulaDescriptor(
        equation: "Strain = softCap((6.2 x log10(acute + 1))^1.08 + clamp(8 x (acute/chronic - 1), -1.5, 4.5)) + 0.5",
        rows: [
            LabFormulaRowModel(
                title: "Acute load curve",
                formula: "L = (6.2 x log10(acute + 1))^1.08",
                value: String(format: "%.2f", snapshot.expandedLoad),
                detail: "Acute load today: \(String(format: "%.2f", snapshot.acuteLoad)).",
                isHighlighted: highlightLoad
            ),
            LabFormulaRowModel(
                title: "Load-ratio adjustment",
                formula: "clamp(8 x (acute/chronic - 1), -1.5, 4.5)",
                value: signedText(snapshot.ratioAdjustment, digits: 2),
                detail: "Current acute/chronic ratio: \(String(format: "%.2f", snapshot.loadRatio)).",
                isHighlighted: highlightLoad
            ),
            LabFormulaRowModel(
                title: "Soft cap",
                formula: "21 x (1 - e^(-(preSoftCap / 18)))",
                value: String(format: "%.2f", snapshot.softCappedScore),
                detail: "Pre-soft-cap score: \(String(format: "%.2f", snapshot.preSoftCapScore)).",
                isHighlighted: report.factor != .strainLoad
            ),
            LabFormulaRowModel(
                title: "Baseline lift",
                formula: "+0.5",
                value: String(format: "%.2f", snapshot.finalStrainScore),
                detail: "The final +0.5 keeps the scale from feeling dead at the floor.",
                isHighlighted: false
            )
        ]
    )
}

@MainActor
private func readinessFormulaDescriptor(report: NutrivanceTuningReport, context: TuningReportLabContext) -> LabFormulaDescriptor {
    let highlightRecoveryReserve = report.factor == .sleep || report.factor == .rhr || report.factor == .readinessBlend || report.factor == .composite
    let highlightHRV = report.factor == .hrv || report.factor == .readinessBlend || report.factor == .composite
    let highlightStrain = report.factor == .strainLoad || report.factor == .readinessBlend || report.factor == .composite

    return LabFormulaDescriptor(
        equation: "Readiness = (0.70 x Recovery) + (0.10 x HRVTrend) - (0.25 x normalizedStrain) + 25",
        rows: [
            LabFormulaRowModel(
                title: "Recovery reserve",
                formula: "0.70 x Recovery",
                value: String(format: "%.2f", context.recoveryValue * 0.70),
                detail: "Sleep and RHR affect readiness mainly upstream through recovery reserve.",
                isHighlighted: highlightRecoveryReserve
            ),
            LabFormulaRowModel(
                title: "HRV trend support",
                formula: "0.10 x HRVTrend",
                value: String(format: "%.2f", context.hrvTrendValue * 0.10),
                detail: "Current HRV trend score: \(String(format: "%.0f", context.hrvTrendValue)).",
                isHighlighted: highlightHRV
            ),
            LabFormulaRowModel(
                title: "Strain drag",
                formula: "-0.25 x normalizedStrain",
                value: signedText(-(context.normalizedStrain * 0.25), digits: 2),
                detail: "Normalized strain today: \(String(format: "%.0f", context.normalizedStrain))/100.",
                isHighlighted: highlightStrain
            ),
            LabFormulaRowModel(
                title: "Offset",
                formula: "+25",
                value: "25.00",
                detail: "The offset keeps the readiness scale usable before recovery and strain are blended.",
                isHighlighted: false
            )
        ]
    )
}

private func labOptional(_ value: Double?, digits: Int) -> String {
    guard let value else { return "n/a" }
    return String(format: "%.\(digits)f", value)
}

private func signedText(_ value: Double, digits: Int) -> String {
    let magnitude = String(format: "%.\(digits)f", abs(value))
    return value >= 0 ? "+\(magnitude)" : "-\(magnitude)"
}

// MARK: - Metric extensions

private extension NutrivanceTuningMetric {
    var accentColor: Color {
        switch self {
        case .recovery: return .green
        case .strain: return .orange
        case .readiness: return .cyan
        }
    }

    var unitSuffix: String {
        switch self {
        case .strain: return "/21"
        case .recovery, .readiness: return "/100"
        }
    }

    var stackSummary: String {
        switch self {
        case .recovery:
            return "Sleep, Effect HRV, and basal overnight heart rate build the reserve score before the lab layer nudges the visible result."
        case .strain:
            return "Acute load, chronic load, and the soft-capped strain curve create the underlying score before any lab paper biases the display."
        case .readiness:
            return "Recovery reserve, HRV trend support, and strain drag combine into a training-day answer that the lab can then tilt slightly."
        }
    }

    func formatValue(_ value: Double) -> String {
        switch self {
        case .strain:
            return String(format: "%.1f", value)
        case .recovery, .readiness:
            return String(format: "%.0f", value)
        }
    }

    func signedDeltaText(_ value: Double) -> String {
        switch self {
        case .strain:
            return String(format: "%+.1f", value)
        case .recovery, .readiness:
            return String(format: "%+.0f", value)
        }
    }

    func previewLabel(for value: Double) -> String {
        switch self {
        case .recovery:
            switch value {
            case 85...: return "Rebuilt"
            case 70..<85: return "Stable"
            case 50..<70: return "Fragile"
            default: return "Underfilled"
            }
        case .strain:
            switch value {
            case 15...: return "Heavy"
            case 10..<15: return "Working"
            case 6..<10: return "Building"
            default: return "Light"
            }
        case .readiness:
            switch value {
            case 85...: return "Clear"
            case 70..<85: return "Ready"
            case 50..<70: return "Managed"
            default: return "Recover"
            }
        }
    }

    var availableFactors: [NutrivanceTuningFactor] {
        switch self {
        case .recovery:
            return [.sleep, .hrv, .rhr, .composite]
        case .strain:
            return [.strainLoad, .composite]
        case .readiness:
            return [.readinessBlend, .sleep, .hrv, .rhr, .strainLoad]
        }
    }
}

#Preview {
    NavigationStack {
        NutrivanceLabsView()
    }
}
