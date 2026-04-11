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

    @State private var isOrganized = true
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
            isOrganized = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    isOrganized = false
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
    @State private var selectedCardIds: Set<UUID> = []
    @State private var cardContainers: [UUID: CardContainer] = [:]
    @State private var draggingCardCenter: CGPoint? = nil
    @State private var draggingCardId: UUID? = nil
    @State private var canvasScale: CGFloat = 1.0
    @State private var lastScrollOffset: CGPoint = .zero
    @State private var scrollOffset: CGPoint = .zero
    @State private var isLoadingPersistedState: Bool = true
    @State private var showSelectionPopup: Bool = false
    
    private var hasSelection: Bool { !selectedCardIds.isEmpty }
    private var selectedCount: Int { selectedCardIds.count }
    
    private var lastSelectedCardPosition: CGPoint? {
        guard let lastId = selectedCardIds.first else { return nil }
        return cardPositions[lastId]
    }
    
    private func toggleCardSelection(_ cardId: UUID) {
        if selectedCardIds.contains(cardId) {
            selectedCardIds.remove(cardId)
        } else {
            selectedCardIds.insert(cardId)
        }
    }
    
    private func selectCard(_ cardId: UUID) {
        selectedCardIds = [cardId]
    }
    
    private func deselectAllCards() {
        selectedCardIds.removeAll()
    }
    
    private func createStackFromSelection() {
        guard selectedCardIds.count > 1 else { return }
        let selectedReports = sortedReports.filter { selectedCardIds.contains($0.id) }
        guard let firstReport = selectedReports.first else { return }
        
        let basePosition = cardPositions[firstReport.id] ?? .zero
        
        for (index, report) in selectedReports.enumerated() {
            cardPositions[report.id] = CGPoint(
                x: basePosition.x + CGFloat(index) * 4,
                y: basePosition.y + CGFloat(index) * 4
            )
        }
        
        deselectAllCards()
    }
    
    private func createContainerFromSelection() {
        guard selectedCardIds.count >= 1 else { return }
        let selectedReports = sortedReports.filter { selectedCardIds.contains($0.id) }
        guard let firstReport = selectedReports.first else { return }
        
        let containerId = UUID()
        let position = cardPositions[firstReport.id] ?? CGPoint(x: 1500, y: 1000)
        
        cardContainers[containerId] = CardContainer(
            id: containerId,
            position: position,
            cardIds: selectedCardIds.map { $0 }
        )
        
        deselectAllCards()
    }
    
    private let cardWidth: CGFloat = 300
    private let cardHeight: CGFloat = 280
    private let cardSpacing: CGFloat = 16
    private let minScale: CGFloat = 0.3
    private let maxScale: CGFloat = 2.5

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
            loadPersistedState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .freeformCanvasNeedsRefresh)) { _ in
            Task {
                await loadPersistedState()
            }
        }
        .onChange(of: cardPositions) { _, _ in savePersistedState() }
        .onChange(of: cardContainers) { _, _ in savePersistedState() }
        .onChange(of: canvasScale) { _, _ in savePersistedState() }
        .onChange(of: scrollOffset) { _, _ in savePersistedState() }
        .onChange(of: sortByNewestFirst) { _, newValue in
            sortByNewestFirst = newValue
        }
        .onDisappear {
            savePersistedState()
            isOrganized = false
            isHeaderMinimized = false
        }
    }
    
    private func loadPersistedState() {
        Task { @MainActor in
            let persistence = FreeformCanvasPersistence.shared
            if let state = await persistence.loadState(for: metric) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    cardPositions = Dictionary(uniqueKeysWithValues: state.cardPositions.map { ($0.key, $0.value.cgPoint) })
                    cardContainers = Dictionary(uniqueKeysWithValues: state.containers.map { ($0.id, $0.cardContainer) })
                    scrollOffset = state.lastScrollOffset.cgPoint
                    lastScrollOffset = state.lastScrollOffset.cgPoint
                    canvasScale = state.canvasScale
                    sortByNewestFirst = state.sortByNewestFirst
                    isOrganized = state.isOrganized
                }
            } else {
                sortByNewestFirst = sortNewestFirst
                cardPositions = defaultPositions(for: 800)
            }
            isLoadingPersistedState = false
        }
    }
    
    private func savePersistedState() {
        guard !isLoadingPersistedState else { return }
        let state = FreeformCanvasState(
            cardPositions: cardPositions.mapValues { CodablePoint($0) },
            containers: cardContainers.values.map { CodableCardContainer(from: $0) },
            lastScrollOffset: CodablePoint(scrollOffset),
            canvasScale: canvasScale,
            sortByNewestFirst: sortByNewestFirst,
            isOrganized: isOrganized,
            lastModified: Date()
        )
        FreeformCanvasPersistence.shared.saveState(state, for: metric)
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
                    
                    Button {
                        addNewContainer()
                    } label: {
                        Image(systemName: "plus.rectangle.on.rectangle")
                    }
                    .buttonStyle(.bordered)
                    .tint(snapshot.accent)
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
        let baseCanvasWidth: CGFloat = 3000
        let baseCanvasHeight: CGFloat = 2000
        
        return ZoomableCanvasView(
            baseCanvasWidth: baseCanvasWidth,
            baseCanvasHeight: baseCanvasHeight,
            metric: metric,
            snapshot: snapshot,
            isDrawingMode: isDrawingMode,
            canvasDrawing: $canvasDrawing,
            cardPositions: $cardPositions,
            selectedCardIds: $selectedCardIds,
            cardContainers: $cardContainers,
            draggingCardId: $draggingCardId,
            draggingCardCenter: $draggingCardCenter,
            scale: $canvasScale,
            scrollOffset: $scrollOffset,
            cardsNotInContainers: cardsNotInContainers,
            cardWidth: cardWidth,
            minScale: minScale,
            maxScale: maxScale,
            lastSelectedCardPosition: lastSelectedCardPosition,
            hasSelection: hasSelection,
            selectedCount: selectedCount,
            onSelectReport: onSelectReport,
            onOrganizeCardsByMetric: organizeCardsByMetric,
            onCreateContainerWithCard: createContainerWithCard,
            onToggleSelection: toggleCardSelection,
            onSelectCard: selectCard,
            onDeselectAll: deselectAllCards,
            onCreateStackFromSelection: createStackFromSelection,
            onCreateContainerFromSelection: createContainerFromSelection,
            getContainerCards: getContainerCards,
            handleCardDrop: handleCardDrop,
            handleContainerCardDrop: handleContainerCardDrop,
            removeCardFromContainer: { cardId, containerId, position in
                removeCardFromContainer(cardId: cardId, containerId: containerId, atPosition: position)
            },
            reorderCardInContainer: reorderCardInContainer
        )
        .overlay(alignment: .bottomTrailing) {
            zoomControls
                .padding()
        }
        .background(Color.black.opacity(0.3))
    }
    
    private var zoomControls: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    canvasScale = max(minScale, canvasScale - 0.25)
                }
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.title3.weight(.medium))
            }
            .buttonStyle(.bordered)
            .disabled(canvasScale <= minScale)
            
            Text("\(Int(canvasScale * 100))%")
                .font(.caption.monospacedDigit().weight(.medium))
                .frame(width: 50)
            
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    canvasScale = min(maxScale, canvasScale + 0.25)
                }
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.title3.weight(.medium))
            }
            .buttonStyle(.bordered)
            .disabled(canvasScale >= maxScale)
            
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    canvasScale = 1.0
                }
            } label: {
                Image(systemName: "1.magnifyingglass")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
    }
    
    private func organizeCardsByMetric(_ sourceCardId: UUID) {
        guard let sourceReport = sortedReports.first(where: { $0.id == sourceCardId }) else { return }
        let reportMetric = sourceReport.metric
        
        let matchingCards = sortedReports.filter { $0.metric == reportMetric }
        guard matchingCards.count > 1 else { return }
        
        let containerId = UUID()
        let basePosition = cardPositions[sourceCardId] ?? .zero
        
        cardContainers[containerId] = CardContainer(
            id: containerId,
            position: basePosition,
            cardIds: matchingCards.map { $0.id }
        )
        
        for (index, report) in matchingCards.enumerated() {
            cardPositions[report.id] = CGPoint(
                x: basePosition.x + CGFloat(index) * 4,
                y: basePosition.y + CGFloat(index) * 4
            )
        }
        
        selectedCardIds.removeAll()
    }
    
    private func createContainerWithCard(_ cardId: UUID) {
        let containerId = UUID()
        let position = cardPositions[cardId] ?? .zero
        
        cardContainers[containerId] = CardContainer(
            id: containerId,
            position: position,
            cardIds: [cardId]
        )
        
        selectedCardIds.removeAll()
    }
    
    private func addNewContainer() {
        let containerId = UUID()
        let position = CGPoint(x: 1500, y: 1000)
        
        cardContainers[containerId] = CardContainer(
            id: containerId,
            position: position,
            cardIds: []
        )
    }
    
    private func deleteContainer(_ containerId: UUID) {
        cardContainers.removeValue(forKey: containerId)
    }
    
    private func makeContainerSmart(_ containerId: UUID, filter: SmartContainerFilter) {
        if var container = cardContainers[containerId] {
            container.isSmartContainer = true
            container.smartFilter = filter
            cardContainers[containerId] = container
        }
    }
    
    private func editSmartFilter(_ containerId: UUID, filter: SmartContainerFilter) {
        if var container = cardContainers[containerId] {
            container.smartFilter = filter
            cardContainers[containerId] = container
        }
    }
    
    private func getContainerCards(_ containerId: UUID) -> [NutrivanceTuningReport] {
        guard let container = cardContainers[containerId] else { return [] }
        
        if container.isSmartContainer, let filter = container.smartFilter {
            return container.matchingCards(from: sortedReports)
        } else {
            return sortedReports.filter { container.cardIds.contains($0.id) }
        }
    }
    
    private var cardsNotInContainers: [NutrivanceTuningReport] {
        let cardIdsInNonSmartContainers = cardContainers.values
            .filter { !$0.isSmartContainer }
            .flatMap { $0.cardIds }
        
        return sortedReports.filter { !cardIdsInNonSmartContainers.contains($0.id) }
    }

    private func bringCardToFront(_ id: UUID) {
        nextCardZOrder += 1
    }
    
    private func handleCardDrop(cardId: UUID, position: CGPoint) {
        let cardCenter = CGPoint(x: position.x + cardWidth / 2, y: position.y + cardHeight / 2)
        
        for (containerId, container) in cardContainers {
            let containerCards = getContainerCards(containerId)
            let cardAlreadyInContainer = containerCards.contains(where: { $0.id == cardId })
            guard !cardAlreadyInContainer else { continue }
            
            let containerRect = containerDropRect(for: container)
            
            if containerRect.contains(cardCenter) {
                addCardToContainer(cardId: cardId, containerId: containerId)
                return
            }
        }
    }
    
    private func handleContainerCardDrop(cardId: UUID, center: CGPoint, sourceContainerId: UUID) {
        for (containerId, container) in cardContainers {
            if containerId == sourceContainerId && !container.isSmartContainer {
                continue
            }
            
            let containerRect = containerDropRect(for: container)
            
            if containerRect.contains(center) {
                if containerId != sourceContainerId {
                    addCardToContainer(cardId: cardId, containerId: containerId)
                }
                return
            }
        }
        
        removeCardFromContainer(cardId: cardId, containerId: sourceContainerId, atPosition: center)
    }
    
    private func containerDropRect(for container: CardContainer) -> CGRect {
        let containerWidth: CGFloat = 380
        let estimatedHeight: CGFloat = container.isExpanded ? 300 : 80
        return CGRect(
            x: container.position.x - containerWidth / 2,
            y: container.position.y - estimatedHeight / 2,
            width: containerWidth,
            height: estimatedHeight
        )
    }
    
    private func addCardToContainer(cardId: UUID, containerId: UUID) {
        guard var container = cardContainers[containerId] else { return }
        guard !container.isSmartContainer else { return }
        guard !container.cardIds.contains(cardId) else { return }
        
        container.cardIds.append(cardId)
        cardContainers[containerId] = container
        
        selectedCardIds.remove(cardId)
    }
    
    private func removeCardFromContainer(cardId: UUID, containerId: UUID, atPosition: CGPoint? = nil) {
        guard var container = cardContainers[containerId] else { return }
        guard !container.isSmartContainer else { return }
        
        container.cardIds.removeAll { $0 == cardId }
        cardContainers[containerId] = container
        
        if let position = atPosition {
            cardPositions[cardId] = CGPoint(
                x: position.x - cardWidth / 2,
                y: position.y - 140
            )
        }
    }
    
    private func reorderCardInContainer(cardId: UUID, newIndex: Int, containerId: UUID) {
        guard var container = cardContainers[containerId] else { return }
        guard !container.isSmartContainer else { return }
        guard let currentIndex = container.cardIds.firstIndex(of: cardId) else { return }
        
        container.cardIds.remove(at: currentIndex)
        let targetIndex = min(newIndex, container.cardIds.count)
        container.cardIds.insert(cardId, at: targetIndex)
        cardContainers[containerId] = container
    }
}

enum ContainerLayoutMode: String, CaseIterable, Codable {
    case list
    case fan
}

struct SmartContainerFilter: Equatable {
    enum FilterType: String, CaseIterable {
        case factor
        case date
        case month
        case valenceAbove
    }
    
    var filterType: FilterType
    var factorFilter: NutrivanceTuningFactor?
    var dateFilter: Date?
    var monthFilter: Int?
    var yearFilter: Int?
    var valenceThreshold: Double?
}

struct CardContainer: Identifiable, Equatable {
    let id: UUID
    var position: CGPoint
    var cardIds: [UUID]
    var isExpanded: Bool = false
    var layoutMode: ContainerLayoutMode = .list
    var isSmartContainer: Bool = false
    var smartFilter: SmartContainerFilter?
    
    static func == (lhs: CardContainer, rhs: CardContainer) -> Bool {
        lhs.id == rhs.id && lhs.position == rhs.position && lhs.cardIds == rhs.cardIds && lhs.isExpanded == rhs.isExpanded && lhs.layoutMode == rhs.layoutMode && lhs.isSmartContainer == rhs.isSmartContainer && lhs.smartFilter == rhs.smartFilter
    }
    
    func matchingCards(from reports: [NutrivanceTuningReport]) -> [NutrivanceTuningReport] {
        guard isSmartContainer, let filter = smartFilter else {
            return []
        }
        
        return reports.filter { report in
            switch filter.filterType {
            case .factor:
                guard let factorFilter = filter.factorFilter else { return false }
                return report.factor == factorFilter
            case .date:
                guard let dateFilter = filter.dateFilter else { return false }
                let calendar = Calendar.current
                return calendar.isDate(report.createdAt, inSameDayAs: dateFilter)
            case .month:
                guard let month = filter.monthFilter, let year = filter.yearFilter else { return false }
                let calendar = Calendar.current
                let reportMonth = calendar.component(.month, from: report.createdAt)
                let reportYear = calendar.component(.year, from: report.createdAt)
                return reportMonth == month && reportYear == year
            case .valenceAbove:
                guard let threshold = filter.valenceThreshold else { return false }
                return report.computedWeight >= threshold
            }
        }
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

// MARK: - Freeform Canvas Persistence

struct CodablePoint: Codable, Equatable {
    var x: Double
    var y: Double
    
    init(_ point: CGPoint) {
        self.x = point.x
        self.y = point.y
    }
    
    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

struct CodableSmartFilter: Codable, Equatable {
    enum FilterType: String, Codable, CaseIterable {
        case factor
        case date
        case month
        case valenceAbove
    }
    
    var filterType: FilterType
    var factorFilter: String?
    var dateFilter: Date?
    var monthFilter: Int?
    var yearFilter: Int?
    var valenceThreshold: Double?
    
    init(from filter: SmartContainerFilter?) {
        guard let filter = filter else {
            self.filterType = .factor
            return
        }
        self.filterType = FilterType(rawValue: filter.filterType.rawValue) ?? .factor
        self.factorFilter = filter.factorFilter?.rawValue
        self.dateFilter = filter.dateFilter
        self.monthFilter = filter.monthFilter
        self.yearFilter = filter.yearFilter
        self.valenceThreshold = filter.valenceThreshold
    }
    
    var smartFilter: SmartContainerFilter {
        SmartContainerFilter(
            filterType: SmartContainerFilter.FilterType(rawValue: filterType.rawValue) ?? .factor,
            factorFilter: factorFilter.flatMap { NutrivanceTuningFactor(rawValue: $0) },
            dateFilter: dateFilter,
            monthFilter: monthFilter,
            yearFilter: yearFilter,
            valenceThreshold: valenceThreshold
        )
    }
}

struct CodableCardContainer: Codable, Identifiable, Equatable {
    let id: UUID
    var position: CodablePoint
    var cardIds: [UUID]
    var isExpanded: Bool
    var layoutMode: ContainerLayoutMode
    var isSmartContainer: Bool
    var smartFilter: CodableSmartFilter?
    
    init(from container: CardContainer) {
        self.id = container.id
        self.position = CodablePoint(container.position)
        self.cardIds = container.cardIds
        self.isExpanded = container.isExpanded
        self.layoutMode = container.layoutMode
        self.isSmartContainer = container.isSmartContainer
        self.smartFilter = CodableSmartFilter(from: container.smartFilter)
    }
    
    var cardContainer: CardContainer {
        CardContainer(
            id: id,
            position: position.cgPoint,
            cardIds: cardIds,
            isExpanded: isExpanded,
            layoutMode: layoutMode,
            isSmartContainer: isSmartContainer,
            smartFilter: smartFilter?.smartFilter
        )
    }
}

struct FreeformCanvasState: Codable {
    var cardPositions: [UUID: CodablePoint]
    var containers: [CodableCardContainer]
    var lastScrollOffset: CodablePoint
    var canvasScale: Double
    var sortByNewestFirst: Bool
    var isOrganized: Bool
    var lastModified: Date
    
    static let storageKey = "freeform_canvas_state_"
    static let iCloudKey = "iCloud_freeform_canvas_state_"
    
    static func key(for metric: NutrivanceTuningMetric) -> String {
        storageKey + metric.rawValue
    }
    
    static func iCloudKey(for metric: NutrivanceTuningMetric) -> String {
        iCloudKey + metric.rawValue
    }
}

@MainActor
class FreeformCanvasPersistence: ObservableObject {
    static let shared = FreeformCanvasPersistence()
    
    @Published var isSyncing: Bool = false
    @Published var lastSyncDate: Date?
    
    private let userDefaults = UserDefaults.standard
    private var iCloudStore: NSUbiquitousKeyValueStore { NSUbiquitousKeyValueStore.default }
    
    private var iCloudObserver: NSObjectProtocol?
    
    init() {
        setupiCloudObserver()
    }
    
    deinit {
        if let observer = iCloudObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    private func setupiCloudObserver() {
        iCloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: iCloudStore,
            queue: .main
        ) { [weak self] notification in
            self?.handleiCloudChange(notification)
        }
        iCloudStore.synchronize()
    }
    
    private nonisolated func handleiCloudChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let changeReason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else {
            return
        }
        
        Task { @MainActor in
            switch changeReason {
            case NSUbiquitousKeyValueStoreServerChange,
                 NSUbiquitousKeyValueStoreInitialSyncChange:
                self.isSyncing = true
                await self.triggerRefreshFromiCloud()
                self.isSyncing = false
                self.lastSyncDate = Date()
            case NSUbiquitousKeyValueStoreQuotaViolationChange:
                print("iCloud quota exceeded for freeform canvas")
            case NSUbiquitousKeyValueStoreAccountChange:
                await self.handleAccountChange()
            default:
                break
            }
        }
    }
    
    private func handleAccountChange() async {
        for metric in NutrivanceTuningMetric.allCases {
            await loadState(for: metric)
        }
    }
    
    private func triggerRefreshFromiCloud() async {
        NotificationCenter.default.post(name: .freeformCanvasNeedsRefresh, object: nil)
    }
    
    func saveState(_ state: FreeformCanvasState, for metric: NutrivanceTuningMetric) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        
        userDefaults.set(data, forKey: FreeformCanvasState.key(for: metric))
        iCloudStore.set(data, forKey: FreeformCanvasState.iCloudKey(for: metric))
        iCloudStore.synchronize()
    }
    
    func loadState(for metric: NutrivanceTuningMetric) async -> FreeformCanvasState? {
        let localKey = FreeformCanvasState.key(for: metric)
        let iCloudKey = FreeformCanvasState.iCloudKey(for: metric)
        
        if let localData = userDefaults.data(forKey: localKey),
           let iCloudData = iCloudStore.data(forKey: iCloudKey) {
            if let localState = try? JSONDecoder().decode(FreeformCanvasState.self, from: localData),
               let iCloudState = try? JSONDecoder().decode(FreeformCanvasState.self, from: iCloudData) {
                return mergeStates(local: localState, iCloud: iCloudState)
            }
        }
        
        if let iCloudData = iCloudStore.data(forKey: iCloudKey),
           let state = try? JSONDecoder().decode(FreeformCanvasState.self, from: iCloudData) {
            userDefaults.set(iCloudData, forKey: localKey)
            return state
        }
        
        if let localData = userDefaults.data(forKey: localKey),
           let state = try? JSONDecoder().decode(FreeformCanvasState.self, from: localData) {
            return state
        }
        
        return nil
    }
    
    private func mergeStates(local: FreeformCanvasState, iCloud: FreeformCanvasState) -> FreeformCanvasState {
        if iCloud.lastModified > local.lastModified {
            return iCloud
        }
        return local
    }
    
    func deleteState(for metric: NutrivanceTuningMetric) {
        let localKey = FreeformCanvasState.key(for: metric)
        let iCloudKey = FreeformCanvasState.iCloudKey(for: metric)
        
        userDefaults.removeObject(forKey: localKey)
        iCloudStore.removeObject(forKey: iCloudKey)
        iCloudStore.synchronize()
    }
}

extension Notification.Name {
    static let freeformCanvasNeedsRefresh = Notification.Name("freeformCanvasNeedsRefresh")
}

import PencilKit

struct PencilKitCanvasView: UIViewRepresentable {
    @Binding var drawingData: Data?
    @Binding var isDrawingMode: Bool
    @Binding var selectedCardId: UUID?
    let cardPositions: [UUID: CGPoint]
    let cardWidth: CGFloat
    
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
        context.coordinator.onLassoFinished = { strokePath in
            checkLassoSelection(strokePath: strokePath)
        }
        
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
    
    private func checkLassoSelection(strokePath: UIBezierPath) {
        for (cardId, position) in cardPositions {
            let cardRect = CGRect(x: position.x, y: position.y, width: cardWidth, height: 280)
            if strokePath.contains(CGPoint(x: cardRect.midX, y: cardRect.midY)) {
                DispatchQueue.main.async {
                    self.selectedCardId = cardId
                }
            }
        }
    }
    
    class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilKitCanvasView
        var toolPicker: PKToolPicker?
        var onLassoFinished: ((UIBezierPath) -> Void)?
        
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
            
            if let strokes = canvasView.drawing.strokes.last,
               strokes.path.count > 0 {
                let bounds = strokes.renderBounds
                let path = UIBezierPath(rect: bounds)
                onLassoFinished?(path)
            }
        }
    }
}

private struct ZoomableCanvasView: View {
    let baseCanvasWidth: CGFloat
    let baseCanvasHeight: CGFloat
    let metric: NutrivanceTuningMetric
    let snapshot: LabsMetricSnapshot
    let isDrawingMode: Bool
    @Binding var canvasDrawing: [String: Data]
    @Binding var cardPositions: [UUID: CGPoint]
    @Binding var selectedCardIds: Set<UUID>
    @Binding var cardContainers: [UUID: CardContainer]
    @Binding var draggingCardId: UUID?
    @Binding var draggingCardCenter: CGPoint?
    @Binding var scale: CGFloat
    @Binding var scrollOffset: CGPoint
    
    let cardsNotInContainers: [NutrivanceTuningReport]
    let cardWidth: CGFloat
    let minScale: CGFloat
    let maxScale: CGFloat
    var lastSelectedCardPosition: CGPoint?
    var hasSelection: Bool
    var selectedCount: Int
    var onSelectReport: (NutrivanceTuningReport) -> Void
    var onOrganizeCardsByMetric: (UUID) -> Void
    var onCreateContainerWithCard: (UUID) -> Void
    var onToggleSelection: (UUID) -> Void
    var onSelectCard: (UUID) -> Void
    var onDeselectAll: () -> Void
    var onCreateStackFromSelection: () -> Void
    var onCreateContainerFromSelection: () -> Void
    var getContainerCards: (UUID) -> [NutrivanceTuningReport]
    var handleCardDrop: (UUID, CGPoint) -> Void
    var handleContainerCardDrop: (UUID, CGPoint, UUID) -> Void
    var removeCardFromContainer: (UUID, UUID, CGPoint?) -> Void
    var reorderCardInContainer: (UUID, Int, UUID) -> Void
    
    var body: some View {
        let canvasSize = computedCanvasSize
        
        CanvasZoomScrollView(
            canvasSize: canvasSize,
            scale: $scale,
            scrollOffset: $scrollOffset,
            minScale: minScale,
            maxScale: maxScale
        ) {
            ZoomableCanvasContent(
                computedCanvasWidth: canvasSize.width,
                computedCanvasHeight: canvasSize.height,
                metric: metric,
                snapshot: snapshot,
                isDrawingMode: isDrawingMode,
                canvasDrawing: $canvasDrawing,
                cardPositions: $cardPositions,
                selectedCardIds: $selectedCardIds,
                cardContainers: $cardContainers,
                draggingCardId: $draggingCardId,
                draggingCardCenter: $draggingCardCenter,
                scale: $scale,
                cardsNotInContainers: cardsNotInContainers,
                cardWidth: cardWidth,
                lastSelectedCardPosition: lastSelectedCardPosition,
                hasSelection: hasSelection,
                selectedCount: selectedCount,
                onSelectReport: onSelectReport,
                onOrganizeCardsByMetric: onOrganizeCardsByMetric,
                onCreateContainerWithCard: onCreateContainerWithCard,
                onToggleSelection: onToggleSelection,
                onSelectCard: onSelectCard,
                onDeselectAll: onDeselectAll,
                onCreateStackFromSelection: onCreateStackFromSelection,
                onCreateContainerFromSelection: onCreateContainerFromSelection,
                getContainerCards: getContainerCards,
                handleCardDrop: handleCardDrop,
                handleContainerCardDrop: handleContainerCardDrop,
                removeCardFromContainer: removeCardFromContainer,
                reorderCardInContainer: reorderCardInContainer
            )
            .onTapGesture {
                onDeselectAll()
            }
        }
    }
    
    private var computedCanvasSize: CGSize {
        let edgeMargin: CGFloat = 600
        let minExpansion: CGFloat = 500
        
        var minX: CGFloat = 0
        var minY: CGFloat = 0
        var maxX: CGFloat = baseCanvasWidth
        var maxY: CGFloat = baseCanvasHeight
        
        for (_, position) in cardPositions {
            minX = min(minX, position.x)
            minY = min(minY, position.y)
            maxX = max(maxX, position.x + cardWidth)
            maxY = max(maxY, position.y + 280)
        }
        
        for (_, container) in cardContainers {
            minX = min(minX, container.position.x - 250)
            minY = min(minY, container.position.y - 200)
            maxX = max(maxX, container.position.x + 250)
            maxY = max(maxY, container.position.y + 200)
        }
        
        let expandedWidth = max(maxX + edgeMargin, baseCanvasWidth + minExpansion)
        let expandedHeight = max(maxY + edgeMargin, baseCanvasHeight + minExpansion)
        
        return CGSize(width: expandedWidth, height: expandedHeight)
    }
}

private struct CanvasZoomScrollView<Content: View>: UIViewRepresentable {
    let canvasSize: CGSize
    @Binding var scale: CGFloat
    @Binding var scrollOffset: CGPoint
    let minScale: CGFloat
    let maxScale: CGFloat
    let content: Content
    
    init(
        canvasSize: CGSize,
        scale: Binding<CGFloat>,
        scrollOffset: Binding<CGPoint>,
        minScale: CGFloat,
        maxScale: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.canvasSize = canvasSize
        self._scale = scale
        self._scrollOffset = scrollOffset
        self.minScale = minScale
        self.maxScale = maxScale
        self.content = content()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(scale: $scale, scrollOffset: $scrollOffset)
    }
    
    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = minScale
        scrollView.maximumZoomScale = maxScale
        scrollView.bouncesZoom = true
        scrollView.alwaysBounceHorizontal = true
        scrollView.alwaysBounceVertical = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        
        let hostingController = UIHostingController(
            rootView: AnyView(content.frame(width: canvasSize.width, height: canvasSize.height))
        )
        hostingController.view.backgroundColor = .clear
        hostingController.view.frame = CGRect(origin: .zero, size: canvasSize)
        
        scrollView.addSubview(hostingController.view)
        scrollView.contentSize = canvasSize
        scrollView.zoomScale = scale.clamped(to: minScale...maxScale)
        
        context.coordinator.hostingController = hostingController
        context.coordinator.lastCanvasSize = canvasSize
        context.coordinator.updateInsets(for: scrollView)
        
        DispatchQueue.main.async {
            guard !context.coordinator.isSyncingFromScrollView else { return }
            scrollView.contentOffset = scrollOffset
        }
        
        return scrollView
    }
    
    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.hostingController?.rootView = AnyView(
            content.frame(
                width: canvasSize.width,
                height: canvasSize.height
            )
        )
        
        if context.coordinator.lastCanvasSize != canvasSize {
            context.coordinator.hostingController?.view.frame = CGRect(origin: .zero, size: canvasSize)
            scrollView.contentSize = canvasSize
            context.coordinator.lastCanvasSize = canvasSize
        }
        
        let clampedScale = scale.clamped(to: minScale...maxScale)
        if abs(scrollView.zoomScale - clampedScale) > 0.001, !scrollView.isZooming {
            context.coordinator.isSyncingFromBinding = true
            scrollView.setZoomScale(clampedScale, animated: false)
            context.coordinator.isSyncingFromBinding = false
        }
        
        if !scrollView.isDragging && !scrollView.isDecelerating && !scrollView.isZooming {
            let currentOffset = scrollView.contentOffset
            if abs(currentOffset.x - scrollOffset.x) > 0.5 || abs(currentOffset.y - scrollOffset.y) > 0.5 {
                context.coordinator.isSyncingFromBinding = true
                scrollView.setContentOffset(scrollOffset, animated: false)
                context.coordinator.isSyncingFromBinding = false
            }
        }
        
        context.coordinator.updateInsets(for: scrollView)
    }
    
    final class Coordinator: NSObject, UIScrollViewDelegate {
        @Binding var scale: CGFloat
        @Binding var scrollOffset: CGPoint
        var hostingController: UIHostingController<AnyView>?
        var lastCanvasSize: CGSize = .zero
        var isSyncingFromBinding = false
        var isSyncingFromScrollView = false
        
        init(scale: Binding<CGFloat>, scrollOffset: Binding<CGPoint>) {
            self._scale = scale
            self._scrollOffset = scrollOffset
        }
        
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            hostingController?.view
        }
        
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            updateInsets(for: scrollView)
            guard !isSyncingFromBinding else { return }
            isSyncingFromScrollView = true
            scale = scrollView.zoomScale
            scrollOffset = scrollView.contentOffset
            isSyncingFromScrollView = false
        }
        
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !isSyncingFromBinding else { return }
            isSyncingFromScrollView = true
            scrollOffset = scrollView.contentOffset
            isSyncingFromScrollView = false
        }
        
        func updateInsets(for scrollView: UIScrollView) {
            let horizontalInset = max((scrollView.bounds.width - scrollView.contentSize.width) * 0.5, 0)
            let verticalInset = max((scrollView.bounds.height - scrollView.contentSize.height) * 0.5, 0)
            scrollView.contentInset = UIEdgeInsets(
                top: verticalInset,
                left: horizontalInset,
                bottom: verticalInset,
                right: horizontalInset
            )
        }
    }
}

private struct ZoomableCanvasContent: View {
    let computedCanvasWidth: CGFloat
    let computedCanvasHeight: CGFloat
    let metric: NutrivanceTuningMetric
    let snapshot: LabsMetricSnapshot
    let isDrawingMode: Bool
    @Binding var canvasDrawing: [String: Data]
    @Binding var cardPositions: [UUID: CGPoint]
    @Binding var selectedCardIds: Set<UUID>
    @Binding var cardContainers: [UUID: CardContainer]
    @Binding var draggingCardId: UUID?
    @Binding var draggingCardCenter: CGPoint?
    @Binding var scale: CGFloat
    
    let cardsNotInContainers: [NutrivanceTuningReport]
    let cardWidth: CGFloat
    var lastSelectedCardPosition: CGPoint?
    var hasSelection: Bool
    var selectedCount: Int
    var onSelectReport: (NutrivanceTuningReport) -> Void
    var onOrganizeCardsByMetric: (UUID) -> Void
    var onCreateContainerWithCard: (UUID) -> Void
    var onToggleSelection: (UUID) -> Void
    var onSelectCard: (UUID) -> Void
    var onDeselectAll: () -> Void
    var onCreateStackFromSelection: () -> Void
    var onCreateContainerFromSelection: () -> Void
    var getContainerCards: (UUID) -> [NutrivanceTuningReport]
    var handleCardDrop: (UUID, CGPoint) -> Void
    var handleContainerCardDrop: (UUID, CGPoint, UUID) -> Void
    var removeCardFromContainer: (UUID, UUID, CGPoint?) -> Void
    var reorderCardInContainer: (UUID, Int, UUID) -> Void
    
    @State private var originalPositions: [UUID: CGPoint] = [:]
    
    private let cardHeight: CGFloat = 280
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            InfiniteGridView()
                .frame(width: computedCanvasWidth, height: computedCanvasHeight)
                .allowsHitTesting(false)
            
            if isDrawingMode {
                PencilKitCanvasView(
                    drawingData: Binding(
                        get: { canvasDrawing[metric.rawValue] },
                        set: { canvasDrawing[metric.rawValue] = $0 }
                    ),
                    isDrawingMode: .constant(isDrawingMode),
                    selectedCardId: Binding(
                        get: { selectedCardIds.first },
                        set: { newId in selectedCardIds = newId.map { [$0] } ?? [] }
                    ),
                    cardPositions: cardPositions,
                    cardWidth: cardWidth
                )
                .frame(width: computedCanvasWidth, height: computedCanvasHeight)
            }
            
            ForEach(cardsNotInContainers) { report in
                let isSelected = selectedCardIds.contains(report.id)
                let position = cardPositions[report.id] ?? .zero
                
                SelectableLabPaperCard(
                    report: report,
                    metric: metric,
                    accent: snapshot.accent,
                    colorScheme: .dark,
                    cardWidth: cardWidth,
                    isSelected: isSelected,
                    position: position,
                    onTap: {
                        if !isDrawingMode {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                onToggleSelection(report.id)
                            }
                        }
                    },
                    onDoubleTap: {
                        if !isDrawingMode {
                            onSelectReport(report)
                        }
                    },
                    onLongPress: {
                        if !isDrawingMode {
                            onSelectCard(report.id)
                        }
                    },
                    onDragChanged: { cardCenter, dragOffset in
                        if draggingCardId == nil {
                            originalPositions = cardPositions
                        }
                        draggingCardId = report.id
                        draggingCardCenter = cardCenter
                        
                        let otherSelectedIds = selectedCardIds.filter { $0 != report.id }
                        for otherId in otherSelectedIds {
                            if let originalPos = originalPositions[otherId] {
                                cardPositions[otherId] = CGPoint(
                                    x: originalPos.x + dragOffset.width,
                                    y: originalPos.y + dragOffset.height
                                )
                            }
                        }
                    },
                    onDragEnded: { newPosition, totalOffset in
                        cardPositions[report.id] = newPosition
                        
                        let otherSelectedIds = selectedCardIds.filter { $0 != report.id }
                        for otherId in otherSelectedIds {
                            if let originalPos = originalPositions[otherId] {
                                cardPositions[otherId] = CGPoint(
                                    x: originalPos.x + totalOffset.width,
                                    y: originalPos.y + totalOffset.height
                                )
                            }
                        }
                        originalPositions.removeAll()
                        
                        handleCardDrop(report.id, newPosition)
                        draggingCardId = nil
                        draggingCardCenter = nil
                    }
                )
                .zIndex(isSelected ? 1000 : 1)
            }
            
            ForEach(Array(cardContainers), id: \.key) { containerId, container in
                let containerCards = getContainerCards(container.id)
                ContainerView(
                    container: container,
                    cards: containerCards,
                    metric: metric,
                    accent: snapshot.accent,
                    colorScheme: .dark,
                    cardWidth: cardWidth,
                    onPositionChanged: { newPosition in
                        cardContainers[container.id]?.position = newPosition
                    },
                    onToggleExpand: {
                        cardContainers[container.id]?.isExpanded.toggle()
                    },
                    onToggleLayoutMode: { mode in
                        cardContainers[container.id]?.layoutMode = mode
                    },
                    onDelete: {
                        cardContainers.removeValue(forKey: container.id)
                    },
                    onMakeSmart: { _ in },
                    onEditSmartFilter: { _ in },
                    onCardTap: { report in
                        onSelectReport(report)
                    },
                    onCardDragStarted: { cardId, center in
                        draggingCardId = cardId
                        draggingCardCenter = center
                    },
                    onCardDragMoved: { cardId, center in
                        draggingCardId = cardId
                        draggingCardCenter = center
                    },
                    onCardDragEnded: { cardId, center, _ in
                        handleContainerCardDrop(cardId, center, container.id)
                        draggingCardId = nil
                        draggingCardCenter = nil
                    },
                    onCardRemoved: { cardId, center in
                        removeCardFromContainer(cardId, container.id, center)
                    },
                    onCardReordered: { cardId, newIndex in
                        reorderCardInContainer(cardId, newIndex, container.id)
                    },
                    draggingCardId: draggingCardId,
                    draggingCardCenter: draggingCardCenter
                )
                .zIndex(50)
            }
            
            if hasSelection && selectedCount > 0, let lastPos = lastSelectedCardPosition {
                let toolbarY: CGFloat = {
                    let toolbarHeight: CGFloat = 50
                    let bottomThreshold: CGFloat = 300
                    if lastPos.y > bottomThreshold {
                        return lastPos.y - toolbarHeight - 20
                    } else {
                        return lastPos.y + 320
                    }
                }()
                let toolbarX = lastPos.x + 150
                SelectionToolbar(
                    selectedCount: selectedCount,
                    accent: snapshot.accent,
                    position: lastPos,
                    onCreateStack: onCreateStackFromSelection,
                    onCreateContainer: onCreateContainerFromSelection,
                    onDeselect: onDeselectAll
                )
                .position(x: toolbarX, y: toolbarY)
            }
        }
    }
}

private struct SelectionToolbar: View {
    let selectedCount: Int
    let accent: Color
    var position: CGPoint
    var onCreateStack: () -> Void
    var onCreateContainer: () -> Void
    var onDeselect: () -> Void
    
    private var toolbarY: CGFloat {
        let toolbarHeight: CGFloat = 50
        let bottomThreshold: CGFloat = 300
        
        if position.y > bottomThreshold {
            return position.y - toolbarHeight - 20
        } else {
            return position.y + 320
        }
    }
    
    var body: some View {
        HStack(spacing: 16) {
            Text("\(selectedCount) selected")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
            
            Divider()
                .frame(height: 20)
            
            Button {
                onCreateStack()
            } label: {
                Label("Stack", systemImage: "square.stack.3d.up")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .tint(accent)
            
            Button {
                onCreateContainer()
            } label: {
                Label("Container", systemImage: "folder.badge.plus")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .tint(accent)
            
            Divider()
                .frame(height: 20)
            
            Button {
                onDeselect()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

private struct SelectableLabPaperCard: View {
    let report: NutrivanceTuningReport
    let metric: NutrivanceTuningMetric
    let accent: Color
    let colorScheme: ColorScheme
    let cardWidth: CGFloat
    var isSelected: Bool
    var position: CGPoint
    var onTap: () -> Void
    var onDoubleTap: () -> Void
    var onLongPress: (() -> Void)?
    var onDragChanged: ((CGPoint, CGSize) -> Void)?
    var onDragEnded: (CGPoint, CGSize) -> Void

    @GestureState private var dragTranslation: CGSize = .zero
    @State private var isDragging: Bool = false
    @State private var isLongPressing: Bool = false

    private var effectiveScale: CGFloat {
        isDragging ? 1.08 : (isLongPressing ? 1.02 : 1.0)
    }

    private var resolvedPosition: CGPoint {
        CGPoint(
            x: position.x + dragTranslation.width,
            y: position.y + dragTranslation.height
        )
    }

    private var cardDrag: some Gesture {
        DragGesture()
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    if !isSelected {
                        withAnimation(.easeInOut(duration: 0.1)) {
                            isLongPressing = true
                        }
                        onLongPress?()
                    }
                }
                let currentPos = CGPoint(
                    x: position.x + value.translation.width,
                    y: position.y + value.translation.height
                )
                onDragChanged?(currentPos, value.translation)
            }
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                let finalPosition = CGPoint(
                    x: position.x + value.translation.width,
                    y: position.y + value.translation.height
                )
                onDragChanged?(finalPosition, value.translation)
                onDragEnded(finalPosition, value.translation)
                isDragging = false
                isLongPressing = false
            }
    }

    var body: some View {
        MetricStackReportCardContent(
            report: report,
            metric: metric,
            accent: accent,
            colorScheme: colorScheme,
            cardWidth: cardWidth
        )
        .scaleEffect(effectiveScale)
        .shadow(
            color: isSelected ? accent.opacity(0.6) : Color.black.opacity(isDragging ? 0.4 : 0.2),
            radius: isDragging ? 24 : (isSelected ? 16 : 10),
            x: 0,
            y: isDragging ? 18 : (isSelected ? 10 : 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? accent : Color.clear, lineWidth: isSelected ? 3 : 0)
        )
        .position(
            x: resolvedPosition.x + cardWidth / 2,
            y: resolvedPosition.y + 140
        )
        .gesture(cardDrag)
        .onTapGesture(count: 2) {
            onDoubleTap()
        }
        .onTapGesture {
            if !isDragging {
                onTap()
            }
        }
    }
}

private struct CardActionPopup: View {
    let report: NutrivanceTuningReport
    let accent: Color
    let position: CGPoint
    let cardWidth: CGFloat
    var onDismiss: () -> Void
    var onOrganizeAsStack: () -> Void
    var onCreateContainer: () -> Void

    private let cardHeight: CGFloat = 280
    private let popupHeight: CGFloat = 100

    private var popupY: CGFloat {
        position.y + cardHeight + popupHeight > 2000 ? position.y - popupHeight - 10 : position.y + cardHeight + 10
    }

    var body: some View {
        VStack(spacing: 8) {
            Button {
                onOrganizeAsStack()
            } label: {
                Label("Organize as Stack", systemImage: "square.stack.3d.up")
                    .font(.caption.weight(.medium))
            }

            Button {
                onCreateContainer()
            } label: {
                Label("Create Container", systemImage: "rectangle.portrait.on.rectangle.portrait")
                    .font(.caption.weight(.medium))
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accent.opacity(0.3), lineWidth: 1)
        )
        .position(
            x: position.x + cardWidth / 2,
            y: popupY + popupHeight / 2
        )
        .onTapGesture {
            onDismiss()
        }
    }
}

private struct ContainerView: View {
    let container: CardContainer
    let cards: [NutrivanceTuningReport]
    let metric: NutrivanceTuningMetric
    let accent: Color
    let colorScheme: ColorScheme
    let cardWidth: CGFloat
    var onPositionChanged: (CGPoint) -> Void
    var onToggleExpand: () -> Void
    var onToggleLayoutMode: (ContainerLayoutMode) -> Void
    var onDelete: () -> Void
    var onMakeSmart: (SmartContainerFilter) -> Void
    var onEditSmartFilter: (SmartContainerFilter) -> Void
    var onCardTap: (NutrivanceTuningReport) -> Void
    var onCardDragStarted: ((UUID, CGPoint) -> Void)?
    var onCardDragMoved: ((UUID, CGPoint) -> Void)?
    var onCardDragEnded: ((UUID, CGPoint, CGSize) -> Void)?
    var onCardRemoved: ((UUID, CGPoint) -> Void)?
    var onCardReordered: ((UUID, Int) -> Void)?
    var draggingCardId: UUID?
    var draggingCardCenter: CGPoint?
    
    @Namespace private var containerNamespace
    @State private var hasAppeared = false
    
    @GestureState private var containerDragOffset: CGSize = .zero
    @State private var isDraggingContainer: Bool = false
    @State private var showSmartConfig: Bool = false
    @State private var internalCardOrder: [UUID] = []
    @State private var draggingCardInContainer: UUID? = nil
    @State private var cardDragOffset: CGSize = .zero
    
    private let headerHeight: CGFloat = 36
    private let containerCardWidth: CGFloat = 260
    private let containerCardHeight: CGFloat = 160
    private let containerWidth: CGFloat = 560
    private let horizontalPadding: CGFloat = 12
    private let verticalPadding: CGFloat = 12
    
    private let collapsedWidth: CGFloat = 300
    private let collapsedHeight: CGFloat = 200
    private let collapsedCardWidth: CGFloat = 200
    private let collapsedCardHeight: CGFloat = 120
    private var collapsedCardAreaHeight: CGFloat { collapsedHeight - headerHeight }
    
    private func cardOffsetX(for index: Int) -> CGFloat {
        switch index {
        case 0: return -6
        case 1: return 2
        case 2: return 8
        case 3: return -4
        case 4: return 6
        default: return 0
        }
    }
    
    private func cardOffsetY(for index: Int) -> CGFloat {
        switch index {
        case 0: return -8
        case 1: return -2
        case 2: return 6
        case 3: return -4
        case 4: return 4
        default: return 0
        }
    }
    
    private func cardRotation(for index: Int) -> Angle {
        switch index {
        case 0: return .degrees(-3)
        case 1: return .degrees(2)
        case 2: return .degrees(5)
        case 3: return .degrees(-1)
        case 4: return .degrees(4)
        default: return .zero
        }
    }
    
    private var sortedCards: [NutrivanceTuningReport] {
        let orderedIds = internalCardOrder.isEmpty ? cards.map { $0.id } : internalCardOrder
        return orderedIds.compactMap { id in cards.first { $0.id == id } }
    }
    
    private var contentHeight: CGFloat {
        switch container.layoutMode {
        case .list:
            return min(CGFloat(max(cards.count, 1)) * (containerCardHeight + 12), 360)
        case .fan:
            return 220
        }
    }
    
    private var totalHeight: CGFloat {
        headerHeight + contentHeight + verticalPadding * 2
    }
    
    private var activeWidth: CGFloat {
        if container.isExpanded {
            if container.layoutMode == .fan {
                let fanCardWidth: CGFloat = 230
                let overlap: CGFloat = 120
                let leadingInset: CGFloat = 24
                return fanCardWidth + CGFloat(max(cards.count - 1, 0)) * overlap + leadingInset * 2 + horizontalPadding * 2
            }
            return containerWidth
        }
        return collapsedWidth
    }
    
    private var activeHeight: CGFloat {
        if container.isExpanded {
            if container.layoutMode == .fan {
                return headerHeight + 150 + verticalPadding * 2 + 20
            }
            return totalHeight
        }
        return collapsedHeight
    }
    
    private let dropPadding: CGFloat = 30
    
    private var containerBounds: CGRect {
        let centerX = container.position.x + containerDragOffset.width
        let centerY = container.position.y + containerDragOffset.height
        return CGRect(
            x: centerX - (activeWidth + dropPadding) / 2,
            y: centerY - (activeHeight + dropPadding) / 2,
            width: activeWidth + dropPadding,
            height: activeHeight + dropPadding
        )
    }
    
    private var isDropTargeted: Bool {
        guard let draggingId = draggingCardId,
              let center = draggingCardCenter else { return false }
        let cardAlreadyInContainer = cards.contains(where: { $0.id == draggingId })
        guard !cardAlreadyInContainer else { return false }
        return containerBounds.contains(center)
    }
    
    private var currentCenter: CGPoint {
        CGPoint(
            x: container.position.x + containerDragOffset.width,
            y: container.position.y + containerDragOffset.height
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            containerHeader
            containerContent
        }
        .frame(width: activeWidth, height: activeHeight)
        .background(Color.black.opacity(isDropTargeted ? 0.5 : 0.3))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isDropTargeted ? accent : accent.opacity(0.4), lineWidth: isDropTargeted ? 4 : 2)
        )
        .shadow(
            color: isDropTargeted ? accent.opacity(0.5) : Color.black.opacity(0.3),
            radius: isDropTargeted ? 20 : 10,
            x: 0,
            y: isDropTargeted ? 8 : 5
        )
        .scaleEffect(isDropTargeted ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDropTargeted)
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: container.isExpanded)
        .position(currentCenter)
        .gesture(containerDragGesture)
        .onAppear {
            internalCardOrder = cards.map { $0.id }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                hasAppeared = true
            }
        }
        .onChange(of: cards.map { $0.id }) { _, newValue in
            let existingOrder = internalCardOrder.filter { newValue.contains($0) }
            let newIds = newValue.filter { !existingOrder.contains($0) }
            internalCardOrder = existingOrder + newIds
        }
        .sheet(isPresented: $showSmartConfig) {
            SmartContainerConfigView(
                metric: metric,
                existingFilter: container.smartFilter,
                onSave: { filter in
                    if !container.isSmartContainer {
                        onMakeSmart(filter)
                    } else {
                        onEditSmartFilter(filter)
                    }
                    showSmartConfig = false
                }
            )
        }
        .contextMenu {
            contextMenuContent
        }
    }
    
    private var collapsedCardsLayer: some View {
        ZStack {
            ForEach(Array(sortedCards.enumerated()), id: \.element.id) { index, report in
                let targetX: CGFloat = collapsedWidth / 2 + cardOffsetX(for: index)
                let targetY: CGFloat = headerHeight + collapsedCardAreaHeight / 2 + cardOffsetY(for: index)
                let targetOpacity: Double = index < 5 ? 1.0 - Double(index) * 0.12 : 0.0
                let targetRotation: Angle = cardRotation(for: index)
                
                ContainerCardView(
                    report: report,
                    metric: metric,
                    accent: accent,
                    colorScheme: colorScheme,
                    cardWidth: collapsedCardWidth,
                    isDragging: false,
                    onTap: { onCardTap(report) },
                    onDragStarted: { _ in },
                    onDragMoved: { _ in },
                    onDragEnded: { _, _ in },
                    cardHeight: collapsedCardHeight
                )
                .frame(
                    width: collapsedCardWidth,
                    height: collapsedCardHeight
                )
                .scaleEffect(0.92)
                .opacity(targetOpacity)
                .rotationEffect(targetRotation)
                .position(x: targetX, y: targetY)
                .matchedGeometryEffect(id: report.id, in: containerNamespace)
            }
            
            if hasAppeared {
                Text("\(cards.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.opacity)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hasAppeared)
            }
        }
    }

    private var containerDragGesture: some Gesture {
        DragGesture()
            .onChanged { _ in
                if !isDraggingContainer {
                    isDraggingContainer = true
                }
            }
            .updating($containerDragOffset) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                let newPosition = CGPoint(
                    x: container.position.x + value.translation.width,
                    y: container.position.y + value.translation.height
                )
                onPositionChanged(newPosition)
                isDraggingContainer = false
            }
    }
    
    @ViewBuilder
    private var contextMenuContent: some View {
        Button {
            onToggleExpand()
        } label: {
            Label(container.isExpanded ? "Collapse" : "Expand", systemImage: container.isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
        }
        
        Divider()
        
        if !container.isSmartContainer {
            Button {
                showSmartConfig = true
            } label: {
                Label("Make Smart Container", systemImage: "wand.and.stars")
            }
        } else {
            Button {
                showSmartConfig = true
            } label: {
                Label("Edit Smart Filter", systemImage: "pencil")
            }
            Label("Smart Container Active", systemImage: "checkmark.circle")
        }
        
        Divider()
        
        Button(role: .destructive) {
            onDelete()
        } label: {
            Label("Delete Container", systemImage: "trash")
        }
    }
    
    private var containerHeader: some View {
        HStack {
            Image(systemName: container.isSmartContainer ? "wand.and.stars" : "square.stack.3d.up")
                .foregroundStyle(accent)
            
            Text(container.isSmartContainer ? "Smart" : "Stack")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
            
            Text("(\(cards.count))")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            
            Spacer()
            
            if container.isExpanded && cards.count >= 2 {
                Menu {
                    Button {
                        onToggleLayoutMode(.list)
                    } label: {
                        Label("List", systemImage: "list.bullet")
                    }
                    Button {
                        onToggleLayoutMode(.fan)
                    } label: {
                        Label("Fan Deck", systemImage: "square.stack.3d.up")
                    }
                } label: {
                    Image(systemName: container.layoutMode == .list ? "list.bullet" : "square.stack.3d.up")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .menuStyle(.borderlessButton)
            }
            
            Button {
                onToggleExpand()
            } label: {
                Image(systemName: container.isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 8)
        .background(accent.opacity(0.6))
        .contentShape(Rectangle())
        .onTapGesture {
            onToggleExpand()
        }
    }
    
    @ViewBuilder
    private var containerContent: some View {
        if container.isExpanded {
            if container.layoutMode == .fan {
                fanLayout
            } else {
                listLayout
            }
        } else {
            collapsedCardsLayer
        }
    }
    
    private var listLayout: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(sortedCards, id: \.id) { report in
                    ContainerCardView(
                        report: report,
                        metric: metric,
                        accent: accent,
                        colorScheme: colorScheme,
                        cardWidth: (containerWidth - horizontalPadding * 2 - 12) / 2,
                        isDragging: draggingCardId == report.id,
                        onTap: {
                            onCardTap(report)
                        },
                        onDragStarted: { center in
                            draggingCardInContainer = report.id
                            onCardDragStarted?(report.id, center)
                        },
                        onDragMoved: { center in
                            onCardDragMoved?(report.id, center)
                        },
                        onDragEnded: { center, offset in
                            handleCardDragEnded(reportId: report.id, center: center, dragOffset: offset)
                            draggingCardInContainer = nil
                        },
                        cardHeight: containerCardHeight
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
        }
    }
    
    private var fanLayout: some View {
        let fanCardWidth: CGFloat = 230
        let fanCardHeight: CGFloat = 150
        let overlap: CGFloat = 120
        let leadingInset: CGFloat = 24
        let contentWidth = fanCardWidth + CGFloat(max(cards.count - 1, 0)) * overlap + leadingInset * 2
        
        return ScrollView(.horizontal, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                ForEach(Array(sortedCards.enumerated()), id: \.element.id) { index, report in
                    let centeredIndex = Double(index) - Double(max(cards.count - 1, 0)) / 2
                    ContainerCardView(
                        report: report,
                        metric: metric,
                        accent: accent,
                        colorScheme: colorScheme,
                        cardWidth: fanCardWidth,
                        isDragging: draggingCardId == report.id,
                        onTap: {
                            onCardTap(report)
                        },
                        onDragStarted: { center in
                            draggingCardInContainer = report.id
                            onCardDragStarted?(report.id, center)
                        },
                        onDragMoved: { center in
                            onCardDragMoved?(report.id, center)
                        },
                        onDragEnded: { center, offset in
                            handleCardDragEnded(reportId: report.id, center: center, dragOffset: offset)
                            draggingCardInContainer = nil
                        },
                        cardHeight: fanCardHeight
                    )
                    .frame(width: fanCardWidth, height: fanCardHeight)
                    .rotationEffect(.degrees(centeredIndex * 4))
                    .offset(x: leadingInset + CGFloat(index) * overlap, y: 12 + abs(centeredIndex) * 10)
                    .zIndex(Double(index))
                }
            }
            .frame(width: max(contentWidth, containerWidth - horizontalPadding * 2), height: contentHeight, alignment: .topLeading)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
        }
    }
    
    private var dragThreshold: CGFloat { 50 }
    
    private func handleCardDragEnded(reportId: UUID, center: CGPoint, dragOffset: CGSize) {
        let distanceFromOrigin = sqrt(pow(dragOffset.width, 2) + pow(dragOffset.height, 2))
        
        let contentBounds = CGRect(
            x: container.position.x + containerDragOffset.width - activeWidth / 2 + horizontalPadding,
            y: container.position.y + containerDragOffset.height - activeHeight / 2 + headerHeight + verticalPadding,
            width: activeWidth - horizontalPadding * 2,
            height: activeHeight - headerHeight - verticalPadding * 2
        )
        
        let isInsideContent = contentBounds.contains(center)
        
        if distanceFromOrigin > dragThreshold && !isInsideContent {
            onCardRemoved?(reportId, center)
        }
        
        onCardDragEnded?(reportId, center, dragOffset)
    }
    
}

private struct ContainerCardView: View {
    let report: NutrivanceTuningReport
    let metric: NutrivanceTuningMetric
    let accent: Color
    let colorScheme: ColorScheme
    let cardWidth: CGFloat
    var isDragging: Bool
    var onTap: () -> Void
    var onDragStarted: (CGPoint) -> Void
    var onDragMoved: (CGPoint) -> Void
    var onDragEnded: (CGPoint, CGSize) -> Void
    var cardHeight: CGFloat = 160
    
    @GestureState private var dragOffset: CGSize = .zero
    @State private var localIsDragging: Bool = false
    
    private var resolvedPosition: CGPoint {
        CGPoint(
            x: cardWidth / 2 + dragOffset.width,
            y: cardHeight / 2 + dragOffset.height
        )
    }
    
    var body: some View {
        ZStack {
            MetricStackReportCardContent(
                report: report,
                metric: metric,
                accent: accent,
                colorScheme: colorScheme,
                cardWidth: cardWidth,
                cardHeight: cardHeight
            )
            .scaleEffect(localIsDragging ? 1.1 : 1.0)
            .shadow(
                color: localIsDragging ? accent.opacity(0.6) : Color.black.opacity(0.2),
                radius: localIsDragging ? 15 : 5,
                x: 0,
                y: localIsDragging ? 10 : 3
            )
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    if !localIsDragging {
                        localIsDragging = true
                        onDragStarted(resolvedPosition)
                    }
                    onDragMoved(resolvedPosition)
                }
                .updating($dragOffset) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    let finalOffset = dragOffset
                    onDragEnded(resolvedPosition, finalOffset)
                    localIsDragging = false
                }
        )
        .onTapGesture {
            onTap()
        }
    }
}

private struct SmartContainerConfigView: View {
    let metric: NutrivanceTuningMetric
    var existingFilter: SmartContainerFilter?
    var onSave: (SmartContainerFilter) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var filterType: SmartContainerFilter.FilterType = .factor
    @State private var selectedFactor: NutrivanceTuningFactor?
    @State private var selectedDate: Date = Date()
    @State private var selectedMonth: Int = 1
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var valenceThreshold: Double = 0.5
    
    private let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    
    init(metric: NutrivanceTuningMetric, existingFilter: SmartContainerFilter? = nil, onSave: @escaping (SmartContainerFilter) -> Void) {
        self.metric = metric
        self.existingFilter = existingFilter
        self.onSave = onSave
        if let filter = existingFilter {
            _filterType = State(initialValue: filter.filterType)
            _selectedFactor = State(initialValue: filter.factorFilter)
            _selectedDate = State(initialValue: filter.dateFilter ?? Date())
            _selectedMonth = State(initialValue: filter.monthFilter ?? 1)
            _selectedYear = State(initialValue: filter.yearFilter ?? Calendar.current.component(.year, from: Date()))
            _valenceThreshold = State(initialValue: filter.valenceThreshold ?? 0.5)
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Filter Type") {
                    Picker("Type", selection: $filterType) {
                        Text("By Factor").tag(SmartContainerFilter.FilterType.factor)
                        Text("By Date").tag(SmartContainerFilter.FilterType.date)
                        Text("By Month").tag(SmartContainerFilter.FilterType.month)
                        Text("Valence Above").tag(SmartContainerFilter.FilterType.valenceAbove)
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("Filter Settings") {
                    switch filterType {
                    case .factor:
                        Picker("Factor", selection: $selectedFactor) {
                            Text("Select...").tag(nil as NutrivanceTuningFactor?)
                            ForEach(NutrivanceTuningFactor.allCases, id: \.self) { f in
                                Text(f.displayTitle).tag(f as NutrivanceTuningFactor?)
                            }
                        }
                    case .date:
                        DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                    case .month:
                        Picker("Month", selection: $selectedMonth) {
                            ForEach(1...12, id: \.self) { month in
                                Text(months[month - 1]).tag(month)
                            }
                        }
                        Picker("Year", selection: $selectedYear) {
                            ForEach((selectedYear - 5)...(selectedYear + 1), id: \.self) { year in
                                Text(String(year)).tag(year)
                            }
                        }
                    case .valenceAbove:
                        VStack(alignment: .leading) {
                            Text("Minimum Valence: \(valenceThreshold, specifier: "%.2f")")
                            Slider(value: $valenceThreshold, in: 0...1, step: 0.1)
                        }
                    }
                }
            }
            .navigationTitle(existingFilter != nil ? "Edit Smart Container" : "Smart Container")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let filter = SmartContainerFilter(
                            filterType: filterType,
                            factorFilter: selectedFactor,
                            dateFilter: filterType == .date ? selectedDate : nil,
                            monthFilter: filterType == .month ? selectedMonth : nil,
                            yearFilter: filterType == .month ? selectedYear : nil,
                            valenceThreshold: filterType == .valenceAbove ? valenceThreshold : nil
                        )
                        onSave(filter)
                    }
                }
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
    var cardHeight: CGFloat = 280

    var body: some View {
        LabPaperPreview(
            report: report,
            metric: metric,
            accent: accent,
            compact: false,
            compactHeight: cardHeight < 200,
            colorScheme: colorScheme,
            showFooter: true,
            showWeightBar: true,
            weightBarValue: report.resolvedComputedWeight()
        )
        .frame(width: cardWidth, height: cardHeight)
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
    var compactHeight: Bool = false
    var colorScheme: ColorScheme = .dark
    var showFooter: Bool = true
    var showWeightBar: Bool = false
    var weightBarValue: Double = 0
    var backgroundOpacity: Double? = nil
    
    private var isCompact: Bool {
        compact || compactHeight
    }

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
        VStack(alignment: .leading, spacing: isCompact ? 6 : 10) {
            HStack(alignment: .top) {
                Text(report.factor.displayTitle)
                    .font(isCompact ? .caption2.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(textColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(accent.opacity(0.2))
                    )
                Spacer()
                Image(systemName: report.isEnabled ? "checkmark.circle.fill" : "pause.circle.fill")
                    .font(isCompact ? .caption : .body)
                    .foregroundStyle(report.isEnabled ? accent : secondaryTextColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(report.factor.displayTitle) -> \(metric.displayTitle)")
                    .font(isCompact ? .caption.weight(.semibold) : .headline)
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                Text(report.userNote)
                    .font(isCompact ? .caption2 : .subheadline)
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(isCompact ? 2 : 4)
                    .multilineTextAlignment(.leading)
            }

            Spacer()

            if showFooter {
                VStack(alignment: .leading, spacing: 4) {
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

                    HStack {
                        Text(isCompact ? report.createdAt.formatted(date: .abbreviated, time: .omitted) : report.shortAttributionLabel)
                            .lineLimit(1)
                            .foregroundStyle(secondaryTextColor)
                        Spacer()
                        Text(report.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundStyle(secondaryTextColor)
                    }
                    .font(.caption2)
                }
            }
        }
        .padding(isCompact ? 10 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: isCompact ? 16 : 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [cardBackgroundColor, accent.opacity(colorScheme == .dark ? 0.12 : 0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: isCompact ? 16 : 24, style: .continuous)
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
