import SwiftUI
import HealthKit
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Keyboard: Start Page card grid (mirrors `SearchView.searchResultsGridFocusable`)

private extension View {
    @ViewBuilder
    func browserStartPageCardFocusable() -> some View {
        #if targetEnvironment(macCatalyst)
        self.focusable(true)
        #elseif os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            self.focusable(true)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

// MARK: - iPad browser workspace (tabs, search home, persistence)

enum BrowserPageID: String, CaseIterable, Codable, Hashable {
    case search
    case programBuilder
    case dashboard
    case todaysPlan
    case trainingCalendar
    case workoutHistory
    case recoveryScore
    case readiness
    case strainRecovery
    case pastQuests
    case heartZones
    case nutrivanceLabs
    case mindfulnessRealm
    case pathfinder
    case journal
    case sleep
    case stress

    var title: String {
        switch self {
        case .search: return "Start Page"
        case .programBuilder: return "Program Builder"
        case .dashboard: return "Dashboard"
        case .todaysPlan: return "Today's Plan"
        case .trainingCalendar: return "Training Calendar"
        case .workoutHistory: return "Workout History"
        case .recoveryScore: return "Recovery Score"
        case .readiness: return "Readiness"
        case .strainRecovery: return "Strain vs Recovery"
        case .pastQuests: return "Past Quests"
        case .heartZones: return "Heart Zones"
        case .nutrivanceLabs: return "Nutrivance Labs"
        case .mindfulnessRealm: return "Mindfulness Realm"
        case .pathfinder: return "Pathfinder"
        case .journal: return "Journal"
        case .sleep: return "Sleep"
        case .stress: return "Stress"
        case .nutrivanceLabs: return "Nutrivance Labs"
        }
    }

    /// Tab strip, large nav title, and split-view combined titles (e.g. Readiness → "Readiness Check").
    var stripTitle: String {
        switch self {
        case .readiness: return "Readiness Check"
        default: return title
        }
    }

    var symbol: String {
        switch self {
        case .search: return "magnifyingglass"
        case .programBuilder: return "hammer.fill"
        case .dashboard: return "chart.bar.fill"
        case .todaysPlan: return "calendar.badge.clock"
        case .trainingCalendar: return "calendar"
        case .workoutHistory: return "clock.arrow.circlepath"
        case .recoveryScore: return "heart.text.square.fill"
        case .readiness: return "checkmark.seal.fill"
        case .strainRecovery: return "figure.strengthtraining.traditional"
        case .pastQuests: return "trophy.fill"
        case .heartZones: return "heart.circle.fill"
        case .mindfulnessRealm: return "sparkles"
        case .pathfinder: return "point.topleft.down.curvedto.point.bottomright.up"
        case .journal: return "book.fill"
        case .sleep: return "moon.zzz.fill"
        case .stress: return "waveform.path.ecg"
        case .nutrivanceLabs: return "slider.horizontal.3"
        }
    }

    /// Aligns browser pages with the app’s root tab / menu state.
    var rootTab: RootTabSelection {
        switch self {
        case .search: return .search
        case .programBuilder: return .programBuilder
        case .dashboard: return .dashboard
        case .todaysPlan: return .todaysPlan
        case .trainingCalendar: return .trainingCalendar
        case .workoutHistory: return .workoutHistory
        case .recoveryScore: return .recoveryScore
        case .readiness: return .readiness
        case .strainRecovery: return .strainRecovery
        case .pastQuests: return .pastQuests
        case .heartZones: return .heartZones
        case .mindfulnessRealm: return .mindfulnessRealm
        case .pathfinder: return .pathfinder
        case .journal: return .journal
        case .sleep: return .sleep
        case .stress: return .stress
        case .nutrivanceLabs: return .nutrivanceLabs
        }
    }
}

struct BrowserTabSession: Identifiable, Codable, Hashable {
    var id: UUID
    var currentPage: BrowserPageID
    var query: String
    var title: String

    static func newTab() -> BrowserTabSession {
        BrowserTabSession(id: UUID(), currentPage: .search, query: "", title: "Start Page")
    }
}

struct BrowserHomeWidgetConfig: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var subtitle: String
    var page: BrowserPageID

    init(id: UUID = UUID(), title: String, subtitle: String, page: BrowserPageID) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.page = page
    }
}

@MainActor
final class BrowserWorkspaceState: ObservableObject {
    @Published var tabs: [BrowserTabSession]
    @Published var selectedTabID: UUID
    @Published var favorites: [BrowserPageID]
    @Published var widgets: [BrowserHomeWidgetConfig]

    private var pendingSelectionSaveWorkItem: DispatchWorkItem?
    private var pendingNavSyncWorkItem: DispatchWorkItem?

    private static let storageKey = "nutrivance.browserWorkspace.v1"
    private let cloudKey = "nutrivance.browserWorkspace.v1"
    private let cloud = NSUbiquitousKeyValueStore.default

    private struct Persisted: Codable {
        var tabs: [BrowserTabSession]
        var selectedTabID: UUID
        var favorites: [BrowserPageID]
        var widgets: [BrowserHomeWidgetConfig]
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(Persisted.self, from: data) {
            tabs = decoded.tabs
            selectedTabID = decoded.selectedTabID
            favorites = decoded.favorites
            widgets = decoded.widgets
        } else {
            let first = BrowserTabSession.newTab()
            tabs = [first]
            selectedTabID = first.id
            favorites = [.dashboard, .programBuilder, .strainRecovery]
            widgets = []
        }
        normalizeSelectionIfNeeded()
        
        #if targetEnvironment(macCatalyst)
        syncFromCloudAsync()
        #endif
    }
    
    #if targetEnvironment(macCatalyst)
    private func syncFromCloudAsync() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.cloud.synchronize()
            if let cloudData = self?.cloud.data(forKey: self?.cloudKey ?? ""),
               let decoded = try? JSONDecoder().decode(Persisted.self, from: cloudData),
               let tabs = decoded.tabs as [BrowserTabSession]?,
               let selectedTabID = decoded.selectedTabID as UUID?,
               let favorites = decoded.favorites as [BrowserPageID]?,
               let widgets = decoded.widgets as [BrowserHomeWidgetConfig]? {
                
                DispatchQueue.main.async {
                    if !tabs.isEmpty {
                        self?.tabs = tabs
                        self?.selectedTabID = selectedTabID
                        self?.favorites = favorites
                        self?.widgets = widgets
                        self?.normalizeSelectionIfNeeded()
                    }
                }
            }
        }
    }
    #endif

    private func normalizeSelectionIfNeeded() {
        if tabs.isEmpty {
            let t = BrowserTabSession.newTab()
            tabs = [t]
            selectedTabID = t.id
            return
        }
        if !tabs.contains(where: { $0.id == selectedTabID }) {
            selectedTabID = tabs[0].id
        }
    }

    func save() {
        pendingSelectionSaveWorkItem?.cancel()
        pendingSelectionSaveWorkItem = nil
        normalizeSelectionIfNeeded()
        let payload = Persisted(tabs: tabs, selectedTabID: selectedTabID, favorites: favorites, widgets: widgets)
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
            #if targetEnvironment(macCatalyst)
            cloud.set(data, forKey: cloudKey)
            #endif
        }
    }

    private func scheduleSelectionSave() {
        pendingSelectionSaveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingSelectionSaveWorkItem = nil
            self?.save()
        }
        pendingSelectionSaveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
    }

    func scheduleNavSync(onSync: @escaping () -> Void) {
        pendingNavSyncWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingNavSyncWorkItem = nil
            onSync()
        }
        pendingNavSyncWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    func selectedTab() -> BrowserTabSession? {
        tabs.first { $0.id == selectedTabID }
    }

    func addTab() {
        let t = BrowserTabSession.newTab()
        tabs.append(t)
        selectedTabID = t.id
        save()
    }

    func closeTab(_ id: UUID) {
        tabs.removeAll { $0.id == id }
        normalizeSelectionIfNeeded()
        save()
    }

    func closeSelectedTab() {
        closeTab(selectedTabID)
    }

    func closeOtherTabs() {
        guard let current = selectedTab() else { return }
        tabs = [current]
        selectedTabID = current.id
        save()
    }

    func selectTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
        scheduleSelectionSave()
    }

    func selectPreviousTab() {
        guard let idx = tabs.firstIndex(where: { $0.id == selectedTabID }), !tabs.isEmpty else { return }
        let newIdx = idx == 0 ? tabs.count - 1 : idx - 1
        selectedTabID = tabs[newIdx].id
        scheduleSelectionSave()
    }

    func selectNextTab() {
        guard let idx = tabs.firstIndex(where: { $0.id == selectedTabID }), !tabs.isEmpty else { return }
        selectedTabID = tabs[(idx + 1) % tabs.count].id
        scheduleSelectionSave()
    }
}

/// Identifies the active browser full-screen page presentation.
private struct BrowserFullscreenPresentation: Identifiable {
    let id = UUID()
    let page: BrowserPageID
}

private struct OpenQuicklyDuplicateChoice {
    var page: BrowserPageID
    var otherTabIDs: [UUID]
}

#if canImport(UIKit)
/// Last scene whose window became key (`NutrivanceSceneMenuRouter` updates this from `UIWindow.didBecomeKeyNotification`).
final class BrowserFocusedSceneTracker {
    static let shared = BrowserFocusedSceneTracker()
    private var focusedScenePersistentIdentifier: String?
    private init() {}

    func adoptKeyScene(_ scene: UIWindowScene?) {
        adoptKeyScenePersistentIdentifier(NutrivanceSceneMenuRouter.scenePersistentIdentifier(scene))
    }

    func adoptKeyScenePersistentIdentifier(_ persistentIdentifier: String?) {
        guard let persistentIdentifier else { return }
        focusedScenePersistentIdentifier = persistentIdentifier
    }

    func clearScenePersistentIdentifier(_ persistentIdentifier: String) {
        guard focusedScenePersistentIdentifier == persistentIdentifier else { return }
        focusedScenePersistentIdentifier = nil
    }

    var focusedScene: UIWindowScene? {
        NutrivanceSceneMenuRouter.connectedScene(matchingPersistentIdentifier: focusedScenePersistentIdentifier)
    }
}
#endif

// MARK: - iPad browser shell (Nutrivance Browser)

struct ContentView_iPad: View {
    private enum SplitPane: String {
        case left
        case right
    }

    private static let tabBarDriftAnimation = Animation.easeInOut(duration: 4).repeatForever(autoreverses: true)
    private static let minimumWindowWidth: CGFloat = 500

    // MARK: State

    @EnvironmentObject private var navigationState: NavigationState
    @EnvironmentObject private var searchState: SearchState
    @StateObject private var browserWorkspace = BrowserWorkspaceState()
    @FocusState private var focusedAddressBarTabID: UUID?
    /// Next tap on this tab’s chip (same pane) opens the address field — first tap selects / focuses the tab only.
    @State private var chipAddressBarArmedTabIDSingle: UUID?
    @State private var chipAddressBarArmedTabIDSplitLeft: UUID?
    @State private var chipAddressBarArmedTabIDSplitRight: UUID?
    @State private var previousPageBeforeSearch: BrowserPageID?
    @State private var showCustomizeSearchHome = false
    @State private var showAllTabsGrid = false
    @State private var animationPhase: Double = 0
    @State private var splitModeEnabled = false
    @State private var splitLeftTabIDs: [UUID] = []
    @State private var splitLeftActiveIdx: Int = 0
    @State private var splitRightTabIDs: [UUID] = []
    @State private var splitRightActiveIdx: Int = 0
    @State private var focusedSplitPane: SplitPane = .left
    @State private var lastInteractedRightPaneTabID: UUID?
    @State private var lastInteractedLeftPaneTabID: UUID?
    /// Left pane’s share of the split (excluding the drag handle), 0.18…0.82.
    @State private var splitPaneFraction: CGFloat = 0.5
    @State private var splitResizeDragStartFraction: CGFloat?
    @State private var isSplitResizeDragging = false
    @State private var browserFullscreenPresentation: BrowserFullscreenPresentation?
    @State private var showBrowserOpenQuickly = false
    @State private var openQuicklyQuery = ""
    @State private var openQuicklySelectedIndex = 0
    @State private var openQuicklyDuplicate: OpenQuicklyDuplicateChoice?
    @State private var openQuicklyFieldFocused = false
#if canImport(UIKit)
    @State private var windowScene: UIWindowScene?
    @State private var windowScenePersistentIdentifier: String?
#endif

    private static let splitResizeHandleWidth: CGFloat = 10
    private static let splitMinPaneFraction: CGFloat = 0.18
    private static let splitMaxPaneFraction: CGFloat = 0.82
    /// Unified chrome row + hairline under it (overlay panel anchors below this).
    private static let browserAddressChromeHeight: CGFloat = 52.5

    // MARK: Body

    var body: some View {
        NavigationStack { composedBrowserView }
            .fullScreenCover(item: $browserFullscreenPresentation) { item in
                BrowserFullscreenShell(
                    page: item.page,
                    onDismiss: { browserFullscreenPresentation = nil }
                )
                .environmentObject(navigationState)
                .environmentObject(searchState)
            }
            .overlay {
                if showBrowserOpenQuickly {
                    BrowserOpenQuicklyPanel(
                        query: $openQuicklyQuery,
                        selectedIndex: $openQuicklySelectedIndex,
                        isFocused: $openQuicklyFieldFocused,
                        matches: openQuicklyMatches,
                        onPick: { openQuicklyApply(page: $0, forceNewTab: $1) },
                        onCancel: { dismissBrowserOpenQuickly() }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .center)))
                    .zIndex(200)
                }
            }
            .onChange(of: showBrowserOpenQuickly) { _, isShowing in
                if isShowing {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        openQuicklyFieldFocused = true
                    }
                } else {
                    openQuicklyFieldFocused = false
                }
            }
            .animation(.easeOut(duration: 0.22), value: showBrowserOpenQuickly)
            .confirmationDialog(
                "Destination already open",
                isPresented: Binding(
                    get: { openQuicklyDuplicate != nil },
                    set: { if !$0 { openQuicklyDuplicate = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Switch to existing tab") {
                    if let id = openQuicklyDuplicate?.otherTabIDs.first {
                        selectBrowserTabAndSyncSplit(id)
                    }
                    openQuicklyDuplicate = nil
                }
                Button("Open new tab") {
                    if let p = openQuicklyDuplicate?.page {
                        openQuicklyOpenInNewTab(page: p)
                    }
                    openQuicklyDuplicate = nil
                }
                Button("Cancel", role: .cancel) {
                    openQuicklyDuplicate = nil
                }
            } message: {
                if let p = openQuicklyDuplicate?.page {
                    Text("\"\(p.stripTitle)\" is already open in another tab.")
                }
            }
            #if targetEnvironment(macCatalyst)
            .onKeyPress(KeyEquivalent("l"), phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                handleCmdLForSearch()
                return .handled
            }
            .onKeyPress(KeyEquivalent("o"), phases: .down) { press in
                guard press.modifiers.contains(.command), press.modifiers.contains(.shift) else { return .ignored }
                presentOrToggleBrowserOpenQuickly()
                return .handled
            }
            .onKeyPress(KeyEquivalent("f"), phases: .down) { press in
                guard press.modifiers.contains(.command), press.modifiers.contains(.shift) else { return .ignored }
                toggleBrowserFullscreenPresentation()
                return .handled
            }
            .onKeyPress(.escape, phases: .down) { _ in
                handleEscapeKey()
                return .handled
            }
            .modifier(BrowserFavoriteSlotKeyCommandsModifier(onSlot: { openFavoriteSlotIfAvailable(index: $0) }))
            #endif
    }

    private var composedBrowserView: some View {
        applyPlatformBackgrounds(
            to: applyBrowserCommandObservers(
                to: applyBrowserStateObservers(to: browserScaffoldView)
            )
        )
    }

    private var browserScaffoldView: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                if splitModeEnabled {
                    splitUnifiedChromeRow
                } else {
                    unifiedBrowserChromeRow
                }
                Rectangle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(height: 0.5)
                contentArea
            }
            addressBarSuggestionsOverlay
        }
        .frame(minWidth: Self.minimumWindowWidth)
        .background(activeBackgroundGradient)
        .navigationTitle(browserNavigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCustomizeSearchHome = true
                } label: {
                    Label("Customize Start Page", systemImage: "slider.horizontal.3")
                }
                .catalystDesktopFocusable()
            }
        }
        .sheet(isPresented: $showCustomizeSearchHome) {
            BrowserSearchHomeCustomizeSheet(
                favorites: $browserWorkspace.favorites,
                widgets: $browserWorkspace.widgets,
                onCommit: { browserWorkspace.save() }
            )
        }
        .sheet(isPresented: $showAllTabsGrid) {
            BrowserAllTabsGridView(
                tabs: browserWorkspace.tabs,
                selectedTabID: browserWorkspace.selectedTabID,
                onSelect: { id in
                    browserWorkspace.selectTab(id)
                    focusedAddressBarTabID = nil
                    showAllTabsGrid = false
                },
                onClose: { id in
                    closeBrowserTab(id)
                }
            )
        }
    }

    private var addressSuggestionsContext: (tabID: UUID, query: String)? {
        guard let tid = focusedAddressBarTabID,
              let raw = tab(for: tid)?.query else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return (tid, raw)
    }

    @ViewBuilder
    private var addressBarSuggestionsOverlay: some View {
        if let ctx = addressSuggestionsContext {
            ZStack(alignment: .top) {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture {
                        focusedAddressBarTabID = nil
                    }
                BrowserAddressBarSuggestionsPanel(
                    favorites: browserWorkspace.favorites,
                    widgets: browserWorkspace.widgets,
                    matches: searchResults(for: ctx.query),
                    onPickPage: { page in
                        open(page, for: ctx.tabID)
                        focusedAddressBarTabID = nil
                    }
                )
                .padding(.horizontal, 14)
                .padding(.top, Self.browserAddressChromeHeight + 6)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
            .animation(
                .spring(response: 0.4, dampingFraction: 0.86),
                value: addressSuggestionsContext.map { "\($0.tabID.uuidString)|\($0.query)" } ?? ""
            )
            .zIndex(50)
        }
    }

    // MARK: Observers & platform chrome

    private func applyBrowserStateObservers<V: View>(to view: V) -> some View {
        view
            .onAppear {
                syncGlobalNavigation()
                syncLegacySearchStateFromSelectedTab()
                startTabBarAnimation()
            }
            .onChange(of: browserWorkspace.selectedTabID) { _, _ in
                browserWorkspace.scheduleNavSync { syncGlobalNavigation() }
            }
            .onChange(of: browserWorkspace.tabs) { _, _ in
                normalizeSplitState()
                browserWorkspace.scheduleNavSync { syncGlobalNavigation() }
            }
            .onChange(of: browserWorkspace.favorites) { _, _ in
                browserWorkspace.save()
            }
            .onChange(of: browserWorkspace.widgets) { _, _ in
                browserWorkspace.save()
            }
            .onChange(of: focusedAddressBarTabID) { _, newID in
                syncSplitPaneWithAddressBarFocus(newID)
            }
    }

    private func applyBrowserCommandObservers<V: View>(to view: V) -> some View {
        applyBrowserCommandObserversTabAndGlobalCycles(
            to: applyBrowserCommandObserversSplitAndSheets(
                to: applyBrowserCommandObserversCoreFileCommands(to: view)
            )
        )
    }

    private func applyBrowserCommandObserversCoreFileCommands<V: View>(to view: V) -> some View {
        view
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceBrowserNewTab)) { notification in
                guard shouldHandleBrowserNotification(notification.object) else { return }
                clearAllChipAddressBarArms()
                browserWorkspace.addTab()
                assignFocusedPaneToCurrentTab()
                focusedAddressBarTabID = browserWorkspace.selectedTabID
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceBrowserCloseTab)) { notification in
                guard shouldHandleBrowserNotification(notification.object) else { return }
                selectFocusedPaneBeforeCommand()
                let id = browserWorkspace.selectedTabID
                closeBrowserTab(id)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceBrowserCloseOtherTabs)) { notification in
                guard shouldHandleBrowserNotification(notification.object) else { return }
                selectFocusedPaneBeforeCommand()
                browserWorkspace.closeOtherTabs()
                normalizeSplitState()
                focusedAddressBarTabID = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceBrowserCloseWindow)) { notification in
                guard shouldHandleBrowserNotification(notification.object) else { return }
                closeWindow()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceBrowserFocusAddressBar)) { notification in
                guard shouldHandleBrowserNotification(notification.object) else { return }
                focusAddressBarForKeyboardShortcut()
            }
    }

    /// ⌘L (Safari-style): sync selection, then focus so the active tab morphs into the capsule search field.
    private func focusAddressBarForKeyboardShortcut() {
        clearAllChipAddressBarArms()
        guard let id = activeTabID() else { return }
        browserWorkspace.selectTab(id)
        if splitModeEnabled {
            if let li = splitLeftTabIDs.firstIndex(of: id) {
                focusedSplitPane = .left
                splitLeftActiveIdx = li
            } else if let ri = splitRightTabIDs.firstIndex(of: id) {
                focusedSplitPane = .right
                splitRightActiveIdx = ri
            }
        }
        DispatchQueue.main.async {
            focusedAddressBarTabID = id
        }
    }

    /// ⌘L: Turn current tab into Search, store previous page for ESC revert.
    private func handleCmdLForSearch() {
        clearAllChipAddressBarArms()
        guard let id = activeTabID(),
              let currentTab = tab(for: id),
              currentTab.currentPage != .search else {
            focusAddressBarForKeyboardShortcut()
            return
        }
        previousPageBeforeSearch = currentTab.currentPage
        open(page: .search)
        DispatchQueue.main.async {
            focusedAddressBarTabID = id
        }
    }

    /// ESC: Dismiss Open Quickly, or revert address bar / Search mode.
    private func handleEscapeKey() {
        if showBrowserOpenQuickly {
            dismissBrowserOpenQuickly()
            return
        }
        guard focusedAddressBarTabID != nil else { return }
        focusedAddressBarTabID = nil
        if let previous = previousPageBeforeSearch {
            open(page: previous)
            previousPageBeforeSearch = nil
        }
    }

    private func applyBrowserCommandObserversSplitAndSheets<V: View>(to view: V) -> some View {
        view
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceBrowserPreviousTab)) { notification in
                guard shouldHandleBrowserNotification(notification.object) else { return }
                clearAllChipAddressBarArms()
                if splitModeEnabled {
                    cyclePrevTabGlobally()
                } else {
                    browserWorkspace.selectPreviousTab()
                    focusedAddressBarTabID = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceBrowserNextTab)) { notification in
                guard shouldHandleBrowserNotification(notification.object) else { return }
                clearAllChipAddressBarArms()
                if splitModeEnabled {
                    cycleNextTabGlobally()
                } else {
                    browserWorkspace.selectNextTab()
                    focusedAddressBarTabID = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceBrowserCycleSplitPaneForward)) { notification in
                guard shouldHandleBrowserNotification(notification.object) else { return }
                cycleSplitPaneFocusForward()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceBrowserCycleSplitPaneReverse)) { notification in
                guard shouldHandleBrowserNotification(notification.object) else { return }
                cycleSplitPaneFocusReverse()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceBrowserShowAllTabs)) { notification in
                guard shouldHandleBrowserNotification(notification.object) else { return }
                showAllTabsGrid = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceBrowserSplitAssignLeft)) { notification in
                guard shouldHandleBrowserNotification(notification.object) else { return }
                moveFocusedTabToOtherPane(target: .left)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceBrowserSplitAssignRight)) { notification in
                guard shouldHandleBrowserNotification(notification.object) else { return }
                moveFocusedTabToOtherPane(target: .right)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceBrowserSwapSplitPanes)) { notification in
                guard shouldHandleBrowserNotification(notification.object) else { return }
                swapSplitPanes()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceBrowserSwapWithLastInteracted)) { notification in
                guard shouldHandleBrowserNotification(notification.object) else { return }
                swapWithLastInteractedTab()
            }
    }

    private func applyBrowserCommandObserversTabAndGlobalCycles<V: View>(to view: V) -> some View {
        view
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceBrowserCyclePrevTabInPane)) { notification in
                guard shouldHandleBrowserNotification(notification.object) else { return }
                cyclePrevTabInFocusedPane()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceBrowserCycleNextTabInPane)) { notification in
                guard shouldHandleBrowserNotification(notification.object) else { return }
                cycleNextTabInFocusedPane()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceBrowserCyclePrevTabGlobally)) { notification in
                guard shouldHandleBrowserNotification(notification.object) else { return }
                cyclePrevTabGlobally()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceBrowserCycleNextTabGlobally)) { notification in
                guard shouldHandleBrowserNotification(notification.object) else { return }
                cycleNextTabGlobally()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceBrowserToggleFullscreen)) { notification in
                guard shouldHandleBrowserNotification(notification.object) else { return }
                toggleBrowserFullscreenPresentation()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceBrowserOpenQuickly)) { notification in
                guard shouldHandleBrowserNotification(notification.object) else { return }
                presentOrToggleBrowserOpenQuickly()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceBrowserOpenFavoriteSlot)) { notification in
                guard shouldHandleBrowserNotification(notification.object) else { return }
                let idx = (notification.userInfo?["index"] as? NSNumber)?.intValue
                    ?? notification.userInfo?["index"] as? Int
                guard let idx, (0..<10).contains(idx) else { return }
                openFavoriteSlotIfAvailable(index: idx)
            }
    }

    private func applyPlatformBackgrounds<V: View>(to view: V) -> some View {
#if canImport(UIKit)
        view
            .background(WindowSceneResolver {
                guard let resolvedScene = $0 else { return }
                windowScene = resolvedScene
                windowScenePersistentIdentifier = NutrivanceSceneMenuRouter.scenePersistentIdentifier(resolvedScene)
            })
            .background(BrowserKeyCommandCaptureView())
#else
        view
#endif
    }

    private func syncLegacySearchStateFromSelectedTab() {
        let query = browserWorkspace.selectedTab()?.query ?? ""
        searchState.searchText = query
    }

    private func startTabBarAnimation() {
        withAnimation(Self.tabBarDriftAnimation) {
            animationPhase = 20
        }
    }

    private func shouldHandleBrowserNotification(_ object: Any?) -> Bool {
#if canImport(UIKit)
        return NutrivanceSceneMenuRouter.shouldHandleSceneTargetedNotification(
            object: object,
            windowScene: windowScene,
            windowScenePersistentIdentifier: windowScenePersistentIdentifier
        )
#else
        return false
#endif
    }

    private func chipTitle(for tab: BrowserTabSession) -> String {
        if tab.currentPage == .search { return BrowserPageID.search.stripTitle }
        return tab.currentPage.stripTitle
    }

    /// Navigation bar title uses each pane’s **current page** (not search-as-you-type preview).
    private func paneNavigationStripTitle(for pane: SplitPane) -> String? {
        guard let id = activeTabIDForPane(pane), let t = tab(for: id) else { return nil }
        return t.currentPage.stripTitle
    }

    private var browserNavigationTitle: String {
        if splitModeEnabled {
            let parts = [paneNavigationStripTitle(for: .left), paneNavigationStripTitle(for: .right)].compactMap { $0 }
            if parts.isEmpty { return "Nutrivance" }
            if parts.count == 1 { return parts[0] }
            return parts.joined(separator: " & ")
        }
        if let t = browserWorkspace.selectedTab() {
            return chipTitle(for: t)
        }
        return "Nutrivance"
    }

    private func presentBrowserFullscreen(page: BrowserPageID) {
        browserFullscreenPresentation = BrowserFullscreenPresentation(page: page)
    }

    private func toggleBrowserFullscreenPresentation() {
        if browserFullscreenPresentation != nil {
            browserFullscreenPresentation = nil
            return
        }
        guard let id = activeTabID(), let t = tab(for: id) else { return }
        browserFullscreenPresentation = BrowserFullscreenPresentation(page: t.currentPage)
    }

    private var openQuicklyMatches: [BrowserSearchResult] {
        searchResults(for: openQuicklyQuery)
    }

    private func presentOrToggleBrowserOpenQuickly() {
        if showBrowserOpenQuickly {
            dismissBrowserOpenQuickly()
        } else {
            clearAllChipAddressBarArms()
            openQuicklyQuery = ""
            openQuicklySelectedIndex = 0
            showBrowserOpenQuickly = true
        }
    }

    private func dismissBrowserOpenQuickly() {
        openQuicklyFieldFocused = false
        showBrowserOpenQuickly = false
        openQuicklyQuery = ""
        openQuicklySelectedIndex = 0
    }

    /// ⌘⇧O: replace the focused tab by default; ⌥↩︎ or explicit choice opens a new tab. Duplicate destinations get a switch/new prompt.
    private func openQuicklyApply(page: BrowserPageID, forceNewTab: Bool) {
        if forceNewTab {
            openQuicklyOpenInNewTab(page: page)
            return
        }
        if page == .search {
            dismissBrowserOpenQuickly()
            guard let active = activeTabID() else { return }
            open(page, for: active)
            return
        }
        guard let active = activeTabID() else { return }
        let others = browserWorkspace.tabs.filter { $0.currentPage == page && $0.id != active }.map(\.id)
        if others.isEmpty {
            dismissBrowserOpenQuickly()
            open(page, for: active)
            return
        }
        dismissBrowserOpenQuickly()
        openQuicklyDuplicate = OpenQuicklyDuplicateChoice(page: page, otherTabIDs: others)
    }

    private func openQuicklyOpenInNewTab(page: BrowserPageID) {
        dismissBrowserOpenQuickly()
        clearAllChipAddressBarArms()
        browserWorkspace.addTab()
        assignFocusedPaneToCurrentTab()
        guard let idx = browserWorkspace.tabs.firstIndex(where: { $0.id == browserWorkspace.selectedTabID }) else { return }
        browserWorkspace.tabs[idx].currentPage = page
        browserWorkspace.tabs[idx].title = page == .search ? BrowserPageID.search.stripTitle : page.stripTitle
        if page == .search {
            browserWorkspace.tabs[idx].query = ""
        }
        browserWorkspace.save()
        focusedAddressBarTabID = nil
        syncGlobalNavigation()
    }

    private func selectBrowserTabAndSyncSplit(_ id: UUID) {
        browserWorkspace.selectTab(id)
        if splitModeEnabled {
            if let li = splitLeftTabIDs.firstIndex(of: id) {
                focusedSplitPane = .left
                splitLeftActiveIdx = li
            } else if let ri = splitRightTabIDs.firstIndex(of: id) {
                focusedSplitPane = .right
                splitRightActiveIdx = ri
            }
        }
        focusedAddressBarTabID = nil
        syncGlobalNavigation()
    }

    /// ⌘⌥1…9 (indices 0…8) and ⌘⌥0 (index 9): open the ordered Start Page favorite in the focused tab.
    private func openFavoriteSlotIfAvailable(index: Int) {
        guard index < browserWorkspace.favorites.count else { return }
        let page = browserWorkspace.favorites[index]
        guard let active = activeTabID() else { return }
        clearAllChipAddressBarArms()
        open(page, for: active)
    }

    private func splitResizeHandle(totalWidth: CGFloat) -> some View {
        let handleW = Self.splitResizeHandleWidth
        let pair = max(totalWidth - handleW, 1)
        return ZStack {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
            Capsule()
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 4, height: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityLabel("Resize split")
        .accessibilityAddTraits(.isButton)
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { g in
                    if !isSplitResizeDragging {
                        isSplitResizeDragging = true
                    }
                    if splitResizeDragStartFraction == nil {
                        splitResizeDragStartFraction = splitPaneFraction
                    }
                    let start = splitResizeDragStartFraction ?? 0.5
                    let delta = g.translation.width / pair
                    let next = min(Self.splitMaxPaneFraction, max(Self.splitMinPaneFraction, start + delta))
                    splitPaneFraction = next
                }
                .onEnded { _ in
                    splitResizeDragStartFraction = nil
                    isSplitResizeDragging = false
                }
        )
    }

    // MARK: Tab strip & address bar (Safari-style compact row)

    /// Compact row: when editing the selected tab, other tabs + capsule field; otherwise all tabs as chips (Safari-style after submit).
    private var unifiedBrowserChromeRow: some View {
        GeometryReader { proxy in
            let editing = focusedAddressBarTabID == browserWorkspace.selectedTabID
            let rowWidth = max(proxy.size.width - 52, 200)
            let tabCount = max(browserWorkspace.tabs.count, 1)
            let tabWidth = min(max((rowWidth - CGFloat(tabCount - 1) * 8) / CGFloat(tabCount), 96), 200)
            HStack(alignment: .center, spacing: 8) {
                if editing {
                    let scrollCap = min(320, max(160, proxy.size.width * 0.38))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(browserWorkspace.tabs.filter { $0.id != browserWorkspace.selectedTabID }) { tab in
                                tabChip(tab: tab, width: 128, side: nil)
                            }
                        }
                        .padding(.leading, 4)
                    }
                    .frame(maxWidth: scrollCap, alignment: .leading)

                    compactAddressBar(for: browserWorkspace.selectedTabID)
                        .frame(maxWidth: .infinity)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(browserWorkspace.tabs) { tab in
                                tabChip(tab: tab, width: tabWidth, side: nil)
                            }
                        }
                        .padding(.leading, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .dropDestination(for: String.self) { items, location in
                        guard let tabIDString = items.first,
                              let tabID = UUID(uuidString: tabIDString) else { return false }
                        return handleTabReorder(tabID: tabID, at: location)
                    }
                }

                addTabButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .animation(.easeInOut(duration: 0.24), value: editing)
        }
        .frame(height: 52)
    }

    /// Split mode: each pane gets its own inactive-tab scroller + search field; resize handle and + stay between / trailing.
    private var splitUnifiedChromeRow: some View {
        GeometryReader { geo in
            let total = geo.size.width
            let handleW = Self.splitResizeHandleWidth
            let pair = max(total - handleW, 1)
            let clampedFraction = min(Self.splitMaxPaneFraction, max(Self.splitMinPaneFraction, splitPaneFraction))
            let leftW = pair * clampedFraction
            let rightW = pair - leftW
            HStack(spacing: 0) {
                splitPaneCompactChrome(pane: .left, outerWidth: leftW)
                    .frame(width: leftW)
                Color.clear
                    .frame(width: handleW)
                HStack(spacing: 8) {
                    splitPaneCompactChrome(pane: .right, outerWidth: max(rightW - 48, 80))
                        .frame(maxWidth: .infinity)
                    addTabButton
                }
                .frame(width: rightW)
            }
            .animation(nil, value: splitPaneFraction)
        }
        .frame(height: 52)
    }

    private func splitPaneCompactChrome(pane: SplitPane, outerWidth: CGFloat) -> some View {
        let activeID = activeTabIDForPane(pane)
        let paneTabs = tabs(for: pane)
        let editing = activeID != nil && focusedAddressBarTabID == activeID
        let tabCount = max(paneTabs.count, 1)
        let tabWidth = min(max((outerWidth - 24 - CGFloat(tabCount - 1) * 8) / CGFloat(tabCount), 80), 148)
        let scrollCap = min(200, max(100, outerWidth * 0.42))
        return HStack(alignment: .center, spacing: 8) {
            if editing, let id = activeID {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(paneTabs.filter { $0.id != id }) { tab in
                            tabChip(tab: tab, width: min(124, outerWidth * 0.4), side: pane)
                        }
                    }
                    .padding(.leading, 4)
                }
                .frame(maxWidth: scrollCap, alignment: .leading)

                compactAddressBar(for: id)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(paneTabs) { tab in
                            tabChip(tab: tab, width: tabWidth, side: pane)
                        }
                    }
                    .padding(.leading, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .animation(.easeInOut(duration: 0.24), value: editing)
    }

    private var addTabButton: some View {
        Button {
            clearAllChipAddressBarArms()
            browserWorkspace.addTab()
            assignFocusedPaneToCurrentTab()
            focusedAddressBarTabID = browserWorkspace.selectedTabID
        } label: {
            Image(systemName: "plus")
                .font(.subheadline.weight(.bold))
                .frame(width: 28, height: 28)
                .background(activeThemeColor.opacity(0.25), in: Circle())
        }
        .buttonStyle(.plain)
        .catalystFocusablePrimaryAction {
            clearAllChipAddressBarArms()
            browserWorkspace.addTab()
            assignFocusedPaneToCurrentTab()
            focusedAddressBarTabID = browserWorkspace.selectedTabID
        }
    }

    private func chipAddressBarArmedTabID(for side: SplitPane?) -> UUID? {
        if splitModeEnabled {
            switch side {
            case .left: return chipAddressBarArmedTabIDSplitLeft
            case .right: return chipAddressBarArmedTabIDSplitRight
            case nil: return nil
            }
        }
        return chipAddressBarArmedTabIDSingle
    }

    private func setChipAddressBarArmedTabID(_ id: UUID?, for side: SplitPane?) {
        if splitModeEnabled {
            switch side {
            case .left: chipAddressBarArmedTabIDSplitLeft = id
            case .right: chipAddressBarArmedTabIDSplitRight = id
            case nil: break
            }
        } else {
            chipAddressBarArmedTabIDSingle = id
        }
    }

    private func clearAllChipAddressBarArms() {
        chipAddressBarArmedTabIDSingle = nil
        chipAddressBarArmedTabIDSplitLeft = nil
        chipAddressBarArmedTabIDSplitRight = nil
    }

    /// First tap selects the tab (chip row); second tap on the same selected tab morphs into the search field.
    private func handleTabChipTap(_ tab: BrowserTabSession, side: SplitPane?) {
        let wasSelected: Bool
        if let side {
            wasSelected = activeTabIDForPane(side) == tab.id
        } else {
            wasSelected = browserWorkspace.selectedTabID == tab.id
        }
        browserWorkspace.selectTab(tab.id)
        if let side {
            focusedSplitPane = side
        }

        if !wasSelected {
            focusedAddressBarTabID = nil
            setChipAddressBarArmedTabID(tab.id, for: side)
            return
        }

        if chipAddressBarArmedTabID(for: side) == tab.id {
            let id = tab.id
            DispatchQueue.main.async {
                focusedAddressBarTabID = id
            }
            setChipAddressBarArmedTabID(nil, for: side)
        } else {
            focusedAddressBarTabID = nil
            setChipAddressBarArmedTabID(tab.id, for: side)
        }
    }

    private func tabChip(tab: BrowserTabSession, width: CGFloat, side: SplitPane?) -> some View {
        let isSelected = browserWorkspace.selectedTabID == tab.id
        return HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: tab.currentPage.symbol)
                    .font(.caption)
                Text(chipTitle(for: tab))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .draggable(tab.id.uuidString)

            Spacer()

            Button {
                closeBrowserTab(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .catalystDesktopFocusable()
        }
        .frame(width: width, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            isSelected
                ? activeThemeColor.opacity(0.9)
                : Color.white.opacity(0.14),
            in: Capsule()
        )
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .contentShape(Capsule())
        .onTapGesture {
            handleTabChipTap(tab, side: side)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .catalystFocusablePrimaryAction {
            handleTabChipTap(tab, side: side)
        }
    }

    private func compactAddressBar(for tabID: UUID) -> some View {
        let binding = browserSearchQueryBinding(for: tabID)
        let query = tab(for: tabID)?.query ?? ""
        let isFocused = focusedAddressBarTabID == tabID
        let accent = addressBarThemeColor(forTab: tabID)
        return HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.subheadline.weight(.medium))
            TextField("Search views, commands, or pages", text: binding)
                .textFieldStyle(.plain)
                .multilineTextAlignment(isFocused ? .leading : .center)
                .focused($focusedAddressBarTabID, equals: tabID)
                .onSubmit {
                    runSearchAndNavigate(for: tabID)
                }
                .animation(.easeInOut(duration: 0.32), value: isFocused)
            if !query.isEmpty {
                Button {
                    clearAddressBar(tabID)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
                .animation(.easeInOut(duration: 0.22), value: query.isEmpty)
                .catalystFocusablePrimaryAction {
                    clearAddressBar(tabID)
                }
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 40)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
        }
        .overlay {
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            accent.opacity(isFocused ? 0.65 : 0.28),
                            Color.primary.opacity(isFocused ? 0.22 : 0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isFocused ? 1.5 : 1
                )
        }
        .animation(.easeInOut(duration: 0.28), value: isFocused)
    }

    private func browserSearchQueryBinding(for tabID: UUID) -> Binding<String> {
        Binding(
            get: { tab(for: tabID)?.query ?? "" },
            set: { newValue in
                guard let idx = browserWorkspace.tabs.firstIndex(where: { $0.id == tabID }) else { return }
                browserWorkspace.tabs[idx].query = newValue
                browserWorkspace.save()
            }
        )
    }

    private func addressBarThemeColor(forTab tabID: UUID) -> Color {
        themeColor(for: visualPage(for: tab(for: tabID)))
    }

    private func clearAddressBar(_ tabID: UUID) {
        guard let idx = browserWorkspace.tabs.firstIndex(where: { $0.id == tabID }) else { return }
        browserWorkspace.selectedTabID = tabID
        browserWorkspace.tabs[idx].query = ""
        browserWorkspace.tabs[idx].currentPage = .search
        browserWorkspace.tabs[idx].title = BrowserPageID.search.stripTitle
        browserWorkspace.save()
        focusedAddressBarTabID = nil
        syncGlobalNavigation()
    }

    private func syncSplitPaneWithAddressBarFocus(_ id: UUID?) {
        guard splitModeEnabled, let id else { return }
        if let li = splitLeftTabIDs.firstIndex(of: id) {
            focusedSplitPane = .left
            splitLeftActiveIdx = li
            browserWorkspace.selectTab(id)
        } else if let ri = splitRightTabIDs.firstIndex(of: id) {
            focusedSplitPane = .right
            splitRightActiveIdx = ri
            browserWorkspace.selectTab(id)
        }
    }

    // MARK: Main content & split panes

    /// Split layout must not use `drawingGroup()`: on Mac Catalyst it rasterizes away UIKit-backed
    /// `NavigationStack` / list content, leaving only the window background visible.
    @ViewBuilder
    private var contentArea: some View {
        if splitModeEnabled {
            GeometryReader { geo in
                let total = max(geo.size.width, 1)
                let height = max(geo.size.height, 1)
                let handleW = Self.splitResizeHandleWidth
                let pair = max(total - handleW, 1)
                let clampedFraction = min(Self.splitMaxPaneFraction, max(Self.splitMinPaneFraction, splitPaneFraction))
                let leftW = max(pair * clampedFraction, 1)
                let rightW = max(pair - leftW, 1)
                HStack(spacing: 0) {
                    splitPaneView(.left)
                        .frame(width: leftW, height: height)
                        .contentShape(Rectangle())
                        .onTapGesture { focusPane(.left) }
                        .dropDestination(for: String.self) { items, _ in
                            handleDropToSplitPane(items: items, target: .left)
                        }
                    splitResizeHandle(totalWidth: total)
                        .frame(width: handleW, height: height)
                    splitPaneView(.right)
                        .frame(width: rightW, height: height)
                        .contentShape(Rectangle())
                        .onTapGesture { focusPane(.right) }
                        .dropDestination(for: String.self) { items, _ in
                            handleDropToSplitPane(items: items, target: .right)
                        }
                }
                .frame(width: total, height: height)
                .animation(nil, value: splitPaneFraction)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: splitModeEnabled)
        } else if let selected = browserWorkspace.selectedTab() {
            ZStack(alignment: .topTrailing) {
                Group {
                    if selected.currentPage == .search {
                        BrowserSearchHomeView(
                            favorites: browserWorkspace.favorites,
                            widgets: browserWorkspace.widgets,
                            query: browserSearchQueryBinding(for: selected.id),
                            results: searchResults(for: selected.query),
                            onPickPage: { page in
                                open(page: page)
                            }
                        )
                        .dropDestination(for: String.self) { items, _ in
                            handleDropToSplitPane(items: items, target: .right)
                        }
                    } else {
                        BrowserPageHost(page: selected.currentPage)
                            .id(selected.currentPage.rawValue)
                            .dropDestination(for: String.self) { items, _ in
                                handleDropToSplitPane(items: items, target: .right)
                            }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                browserFullscreenOverlayButton(page: selected.currentPage)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView("No Tab", systemImage: "square.on.square", description: Text("Create a tab to continue."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Tabs, search & window actions

    /// Single entry for closing a tab from UI, ⌘W, or the All Tabs sheet.
    private func closeBrowserTab(_ id: UUID) {
        if browserWorkspace.tabs.count <= 1 {
            closeWindow()
            return
        }

        var nextTabID: UUID?
        let tabs = browserWorkspace.tabs

        if splitModeEnabled {
            if let leftIdx = splitLeftTabIDs.firstIndex(of: id), leftIdx > 0 {
                nextTabID = splitLeftTabIDs[leftIdx - 1]
            } else if let rightIdx = splitRightTabIDs.firstIndex(of: id), rightIdx > 0 {
                nextTabID = splitRightTabIDs[rightIdx - 1]
            } else if let leftIdx = splitLeftTabIDs.firstIndex(of: id), leftIdx == 0, splitLeftTabIDs.count > 1 {
                nextTabID = splitLeftTabIDs[1]
            } else if let rightIdx = splitRightTabIDs.firstIndex(of: id), rightIdx == 0, splitRightTabIDs.count > 1 {
                nextTabID = splitRightTabIDs[1]
            }
        } else {
            if let idx = tabs.firstIndex(where: { $0.id == id }), idx > 0 {
                nextTabID = tabs[idx - 1].id
            } else if let idx = tabs.firstIndex(where: { $0.id == id }), idx == 0, tabs.count > 1 {
                nextTabID = tabs[1].id
            }
        }

        if splitModeEnabled {
            let wasLeftEmpty = splitLeftTabIDs.isEmpty
            let wasRightEmpty = splitRightTabIDs.isEmpty
            splitLeftTabIDs.removeAll { $0 == id }
            splitRightTabIDs.removeAll { $0 == id }
            if splitModeEnabled {
                if splitLeftTabIDs.isEmpty && wasLeftEmpty == false {
                    splitLeftActiveIdx = 0
                }
                if splitRightTabIDs.isEmpty && wasRightEmpty == false {
                    splitRightActiveIdx = 0
                }
            }
        }
        browserWorkspace.closeTab(id)

        if let next = nextTabID {
            browserWorkspace.selectTab(next)
            if splitModeEnabled {
                if let li = splitLeftTabIDs.firstIndex(of: next) {
                    splitLeftActiveIdx = li
                    focusedSplitPane = .left
                } else if let ri = splitRightTabIDs.firstIndex(of: next) {
                    splitRightActiveIdx = ri
                    focusedSplitPane = .right
                }
            }
        }

        normalizeSplitState()
        focusedAddressBarTabID = nil
        syncGlobalNavigation()
    }

    private func closeTab(_ id: UUID) {
        closeBrowserTab(id)
    }

    private func runSearchAndNavigate(for tabID: UUID) {
        guard let idx = browserWorkspace.tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let trimmed = browserWorkspace.tabs[idx].query.trimmingCharacters(in: .whitespacesAndNewlines)
        browserWorkspace.selectedTabID = tabID
        if trimmed.isEmpty {
            browserWorkspace.tabs[idx].currentPage = .search
            browserWorkspace.tabs[idx].title = BrowserPageID.search.stripTitle
            browserWorkspace.save()
            focusedAddressBarTabID = nil
            syncGlobalNavigation()
            return
        }
        let matches = searchResults(for: trimmed)
        if let first = matches.first {
            browserWorkspace.tabs[idx].currentPage = first.page
            browserWorkspace.tabs[idx].title = first.page.stripTitle
        } else {
            browserWorkspace.tabs[idx].currentPage = .search
            browserWorkspace.tabs[idx].title = BrowserPageID.search.stripTitle
        }
        browserWorkspace.save()
        focusedAddressBarTabID = nil
        syncGlobalNavigation()
    }

    private func open(_ page: BrowserPageID, for tabID: UUID) {
        guard let idx = browserWorkspace.tabs.firstIndex(where: { $0.id == tabID }) else { return }
        browserWorkspace.tabs[idx].currentPage = page
        browserWorkspace.tabs[idx].title = page.stripTitle
        browserWorkspace.selectTab(tabID)
        focusedAddressBarTabID = nil
        syncGlobalNavigation()
    }

    private func open(page: BrowserPageID) {
        guard let id = activeTabID() else { return }
        open(page, for: id)
    }

    private func searchResults(for query: String) -> [BrowserSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = BrowserSearchResult.catalog
        guard !trimmed.isEmpty else { return all }

        return all
            .map { item in
                let title = item.title.lowercased()
                let aliasHits = item.aliases.filter { $0.contains(trimmed) || trimmed.contains($0) }.count
                let exact = title == trimmed ? 1000 : 0
                let starts = title.hasPrefix(trimmed) ? 250 : 0
                let contains = title.contains(trimmed) ? 120 : 0
                let score = exact + starts + contains + aliasHits * 60
                return (item, score)
            }
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in lhs.1 > rhs.1 }
            .map(\.0)
    }

    private func activeTabID() -> UUID? {
        if splitModeEnabled {
            return activeTabIDForPane(focusedSplitPane)
        }
        return browserWorkspace.selectedTabID
    }

    private func tab(for id: UUID?) -> BrowserTabSession? {
        guard let id else { return nil }
        return browserWorkspace.tabs.first(where: { $0.id == id })
    }

    private func updateActiveTab(_ mutate: (inout BrowserTabSession) -> Void) {
        guard let id = activeTabID(),
              let index = browserWorkspace.tabs.firstIndex(where: { $0.id == id }) else { return }
        browserWorkspace.selectedTabID = id
        mutate(&browserWorkspace.tabs[index])
        browserWorkspace.save()
    }

    private func focusPane(_ side: SplitPane) {
        focusedSplitPane = side
        if let id = activeTabIDForPane(side) {
            browserWorkspace.selectTab(id)
            focusedAddressBarTabID = nil
        }
    }

    private func activeTabIDForPane(_ side: SplitPane) -> UUID? {
        if side == .left, !splitLeftTabIDs.isEmpty {
            return splitLeftTabIDs[min(splitLeftActiveIdx, splitLeftTabIDs.count - 1)]
        } else if side == .right, !splitRightTabIDs.isEmpty {
            return splitRightTabIDs[min(splitRightActiveIdx, splitRightTabIDs.count - 1)]
        }
        return nil
    }

    /// ⌃Tab / ⌃⇧Tab — move keyboard focus between split panes (two-pane toggle).
    private func cycleSplitPaneFocusForward() {
        guard splitModeEnabled else { return }
        focusedSplitPane = focusedSplitPane == .left ? .right : .left
        focusPane(focusedSplitPane)
    }

    private func cycleSplitPaneFocusReverse() {
        cycleSplitPaneFocusForward()
    }

    private func swapActiveTabsBetweenSplitPanes() {
        guard splitModeEnabled else { return }
        guard let l = activeTabIDForPane(.left), let r = activeTabIDForPane(.right) else { return }
        if l == r {
            swap(&splitLeftTabIDs, &splitRightTabIDs)
            swap(&splitLeftActiveIdx, &splitRightActiveIdx)
            return
        }
        guard let li = splitLeftTabIDs.firstIndex(of: l), let ri = splitRightTabIDs.firstIndex(of: r) else { return }
        splitLeftTabIDs[li] = r
        splitRightTabIDs[ri] = l
    }

    private func tabs(for side: SplitPane) -> [BrowserTabSession] {
        guard splitModeEnabled else { return browserWorkspace.tabs }
        let ids = side == .left ? splitLeftTabIDs : splitRightTabIDs
        return ids.compactMap { tab(for: $0) }
    }

    @ViewBuilder
    private func splitPaneView(_ side: SplitPane) -> some View {
        if let id = activeTabIDForPane(side), let paneTab = tab(for: id) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if paneTab.currentPage == .search {
                        BrowserSearchHomeView(
                            favorites: browserWorkspace.favorites,
                            widgets: browserWorkspace.widgets,
                            query: browserSearchQueryBinding(for: id),
                            results: searchResults(for: paneTab.query),
                            onPickPage: { page in
                                focusedSplitPane = side
                                browserWorkspace.selectTab(id)
                                open(page: page)
                            }
                        )
                    } else {
                        BrowserPageHost(page: paneTab.currentPage)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // Tab UUID keeps two panes distinct even when both show the same `BrowserPageID`.
                .id(id)
                browserFullscreenOverlayButton(page: paneTab.currentPage)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        } else {
            ContentUnavailableView("Drop a Tab", systemImage: "rectangle.split.2x1", description: Text("Drag a tab here or use Command+Control+Left/Right."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func browserFullscreenOverlayButton(page: BrowserPageID) -> some View {
        Button {
            presentBrowserFullscreen(page: page)
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(10)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Full screen")
        .padding(12)
        .catalystDesktopFocusable()
    }

    private func enableSplit(byAssigningSelectedTabTo side: SplitPane) {
        guard let selected = browserWorkspace.selectedTab() else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if !splitModeEnabled {
                splitModeEnabled = true
                let otherTabs = browserWorkspace.tabs.filter { $0.id != selected.id }
                if side == .left {
                    splitLeftTabIDs = [selected.id]
                    splitLeftActiveIdx = 0
                    splitRightTabIDs = otherTabs.map(\.id)
                    splitRightActiveIdx = 0
                    focusedSplitPane = .left
                } else {
                    splitLeftTabIDs = otherTabs.map(\.id)
                    splitLeftActiveIdx = 0
                    splitRightTabIDs = [selected.id]
                    splitRightActiveIdx = 0
                    focusedSplitPane = .right
                }
            } else if focusedSplitPane == side {
                if side == .left {
                    if !splitLeftTabIDs.contains(selected.id) {
                        splitLeftTabIDs.append(selected.id)
                        splitLeftActiveIdx = splitLeftTabIDs.count - 1
                    }
                } else {
                    if !splitRightTabIDs.contains(selected.id) {
                        splitRightTabIDs.append(selected.id)
                        splitRightActiveIdx = splitRightTabIDs.count - 1
                    }
                }
            } else {
                swapActiveTabsBetweenSplitPanes()
                focusedSplitPane = side
            }
        }
        if splitLeftTabIDs.isEmpty || splitRightTabIDs.isEmpty {
            normalizeSplitState()
            if !splitModeEnabled { return }
        }
        if let id = activeTabIDForPane(side) {
            browserWorkspace.selectTab(id)
        }
        focusedSplitPane = side
    }

    private func swapSplitPanes() {
        guard splitModeEnabled else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            let tempIDs = splitLeftTabIDs
            let tempIdx = splitLeftActiveIdx
            splitLeftTabIDs = splitRightTabIDs
            splitLeftActiveIdx = splitRightActiveIdx
            splitRightTabIDs = tempIDs
            splitRightActiveIdx = tempIdx
            focusedSplitPane = focusedSplitPane == .left ? .right : .left
        }
        focusPane(focusedSplitPane)
        if let l = activeTabIDForPane(.left) {
            lastInteractedLeftPaneTabID = l
        }
        if let r = activeTabIDForPane(.right) {
            lastInteractedRightPaneTabID = r
        }
    }

    private func moveFocusedTabToOtherPane(target: SplitPane) {
        guard splitModeEnabled else {
            enableSplit(byAssigningSelectedTabTo: target)
            return
        }

        let sourcePane = target == .left ? SplitPane.right : SplitPane.left
        guard let tabID = activeTabIDForPane(sourcePane) else { return }

        lastInteractedLeftPaneTabID = nil
        lastInteractedRightPaneTabID = nil

        if target == .left {
            splitLeftTabIDs.append(tabID)
            splitLeftActiveIdx = splitLeftTabIDs.count - 1
            splitRightTabIDs.removeAll { $0 == tabID }
            if splitRightTabIDs.isEmpty {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    splitModeEnabled = false
                    splitLeftTabIDs = []
                    splitRightTabIDs = []
                    splitLeftActiveIdx = 0
                    splitRightActiveIdx = 0
                    splitPaneFraction = 0.5
                }
                if let tab = tab(for: tabID) {
                    browserWorkspace.selectTab(tabID)
                    syncGlobalNavigation()
                }
            } else {
                splitRightActiveIdx = min(splitRightActiveIdx, splitRightTabIDs.count - 1)
            }
        } else {
            splitRightTabIDs.append(tabID)
            splitRightActiveIdx = splitRightTabIDs.count - 1
            splitLeftTabIDs.removeAll { $0 == tabID }
            if splitLeftTabIDs.isEmpty {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    splitModeEnabled = false
                    splitLeftTabIDs = []
                    splitRightTabIDs = []
                    splitLeftActiveIdx = 0
                    splitRightActiveIdx = 0
                    splitPaneFraction = 0.5
                }
                if let tab = tab(for: tabID) {
                    browserWorkspace.selectTab(tabID)
                    syncGlobalNavigation()
                }
            } else {
                splitLeftActiveIdx = min(splitLeftActiveIdx, splitLeftTabIDs.count - 1)
            }
        }
        focusPane(target)
    }

    private func swapWithLastInteractedTab() {
        guard splitModeEnabled else { return }
        
        let otherTabID: UUID?
        if focusedSplitPane == .left {
            otherTabID = lastInteractedRightPaneTabID ?? activeTabIDForPane(.right)
        } else {
            otherTabID = lastInteractedLeftPaneTabID ?? activeTabIDForPane(.left)
        }
        
        guard let otherID = otherTabID,
              let focusedID = activeTabIDForPane(focusedSplitPane) else { return }
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if focusedSplitPane == .left {
                if let li = splitLeftTabIDs.firstIndex(of: focusedID),
                   let ri = splitRightTabIDs.firstIndex(of: otherID) {
                    splitLeftTabIDs[li] = otherID
                    splitRightTabIDs[ri] = focusedID
                    lastInteractedRightPaneTabID = focusedID
                    lastInteractedLeftPaneTabID = otherID
                }
            } else {
                if let ri = splitRightTabIDs.firstIndex(of: focusedID),
                   let li = splitLeftTabIDs.firstIndex(of: otherID) {
                    splitRightTabIDs[ri] = otherID
                    splitLeftTabIDs[li] = focusedID
                    lastInteractedLeftPaneTabID = focusedID
                    lastInteractedRightPaneTabID = otherID
                }
            }
        }
    }

    private func cyclePrevTabInFocusedPane() {
        guard splitModeEnabled else { return }
        if focusedSplitPane == .left {
            if !splitLeftTabIDs.isEmpty {
                splitLeftActiveIdx = (splitLeftActiveIdx - 1 + splitLeftTabIDs.count) % splitLeftTabIDs.count
                focusPane(.left)
            }
        } else {
            if !splitRightTabIDs.isEmpty {
                splitRightActiveIdx = (splitRightActiveIdx - 1 + splitRightTabIDs.count) % splitRightTabIDs.count
                focusPane(.right)
            }
        }
    }

    private func cycleNextTabInFocusedPane() {
        guard splitModeEnabled else { return }
        if focusedSplitPane == .left {
            if !splitLeftTabIDs.isEmpty {
                splitLeftActiveIdx = (splitLeftActiveIdx + 1) % splitLeftTabIDs.count
                focusPane(.left)
            }
        } else {
            if !splitRightTabIDs.isEmpty {
                splitRightActiveIdx = (splitRightActiveIdx + 1) % splitRightTabIDs.count
                focusPane(.right)
            }
        }
    }

    private func cyclePrevTabGlobally() {
        guard splitModeEnabled else { return }
        let allLeftTabs = splitLeftTabIDs
        let allRightTabs = splitRightTabIDs
        guard !allLeftTabs.isEmpty, !allRightTabs.isEmpty else { return }
        let totalTabs = allLeftTabs.count + allRightTabs.count
        guard totalTabs > 0 else { return }
        
        // Calculate current position
        let currentPos = focusedSplitPane == .left
            ? splitLeftActiveIdx
            : allLeftTabs.count + splitRightActiveIdx
        
        // Move to previous, wrapping around
        let newPos = (currentPos - 1 + totalTabs) % totalTabs
        
        if newPos < allLeftTabs.count {
            focusedSplitPane = .left
            splitLeftActiveIdx = newPos
        } else {
            focusedSplitPane = .right
            splitRightActiveIdx = newPos - allLeftTabs.count
        }
        focusPane(focusedSplitPane)
    }

    private func cycleNextTabGlobally() {
        guard splitModeEnabled else { return }
        let allLeftTabs = splitLeftTabIDs
        let allRightTabs = splitRightTabIDs
        guard !allLeftTabs.isEmpty, !allRightTabs.isEmpty else { return }
        let totalTabs = allLeftTabs.count + allRightTabs.count
        guard totalTabs > 0 else { return }
        
        // Calculate current position
        let currentPos = focusedSplitPane == .left
            ? splitLeftActiveIdx
            : allLeftTabs.count + splitRightActiveIdx
        
        // Move to next, wrapping around
        let newPos = (currentPos + 1) % totalTabs
        
        if newPos < allLeftTabs.count {
            focusedSplitPane = .left
            splitLeftActiveIdx = newPos
        } else {
            focusedSplitPane = .right
            splitRightActiveIdx = newPos - allLeftTabs.count
        }
        focusPane(focusedSplitPane)
    }

    private func handleDropToSplitPane(items: [String], target: SplitPane) -> Bool {
        guard let first = items.first, let id = UUID(uuidString: first), tab(for: id) != nil else { return false }
        browserWorkspace.selectTab(id)
        enableSplit(byAssigningSelectedTabTo: target)
        return true
    }

    private func handleTabReorder(tabID: UUID, at location: CGPoint) -> Bool {
        guard let sourceIdx = browserWorkspace.tabs.firstIndex(where: { $0.id == tabID }) else { return false }
        
        let tabChipWidth: CGFloat = 140
        let spacing: CGFloat = 8
        let startPadding: CGFloat = 16
        
        var cumulativeX = startPadding
        for (idx, tab) in browserWorkspace.tabs.enumerated() {
            if tab.id == tabID { continue }
            let targetIdx = cumulativeX + (tabChipWidth / 2) > location.x ? idx : idx + 1
            if sourceIdx < targetIdx {
                cumulativeX += tabChipWidth + spacing
                continue
            }
            var newTabs = browserWorkspace.tabs
            newTabs.remove(at: sourceIdx)
            let insertIdx = min(targetIdx, newTabs.count)
            newTabs.insert(browserWorkspace.tabs[sourceIdx], at: insertIdx)
            browserWorkspace.tabs = newTabs
            browserWorkspace.save()
            return true
        }
        return false
    }

    private func assignFocusedPaneToCurrentTab() {
        guard splitModeEnabled, let current = browserWorkspace.selectedTab() else { return }
        if focusedSplitPane == .left {
            if !splitLeftTabIDs.contains(current.id) {
                splitLeftTabIDs.append(current.id)
                splitLeftActiveIdx = splitLeftTabIDs.count - 1
            } else {
                splitLeftActiveIdx = splitLeftTabIDs.firstIndex(of: current.id) ?? 0
            }
        } else {
            if !splitRightTabIDs.contains(current.id) {
                splitRightTabIDs.append(current.id)
                splitRightActiveIdx = splitRightTabIDs.count - 1
            } else {
                splitRightActiveIdx = splitRightTabIDs.firstIndex(of: current.id) ?? 0
            }
        }
    }

    private func selectFocusedPaneBeforeCommand() {
        guard splitModeEnabled, let id = activeTabID() else { return }
        browserWorkspace.selectTab(id)
    }

    private func closeWindow() {
        #if canImport(UIKit)
        let targetScene = windowScene
            ?? NutrivanceSceneMenuRouter.connectedScene(matchingPersistentIdentifier: windowScenePersistentIdentifier)
            ?? NutrivanceSceneMenuRouter.targetSceneForMenuCommand()
            ?? BrowserFocusedSceneTracker.shared.focusedScene

        guard let windowScene = targetScene else { return }

        // Catalyst / multi-window: close via responder chain (same as macOS window close).
        let closeSel = Selector(("performClose:"))
        if let window = windowScene.windows.first(where: \.isKeyWindow) ?? windowScene.windows.first {
            var responder: UIResponder? = window
            while let current = responder {
                if current.responds(to: closeSel) {
                    current.perform(closeSel, with: nil)
                    return
                }
                responder = current.next
            }
        }

        // Secondary windows or when performClose is unavailable: destroy the scene session.
        for scene in UIApplication.shared.connectedScenes where scene === windowScene {
            UIApplication.shared.requestSceneSessionDestruction(scene.session, options: nil, errorHandler: nil)
        }
        #endif
    }

    // MARK: Split state

    private func exitSplitKeepingNonEmptyPane() {
        if splitLeftTabIDs.isEmpty, !splitRightTabIDs.isEmpty {
            exitSplitKeeping(pane: .right)
        } else if splitRightTabIDs.isEmpty, !splitLeftTabIDs.isEmpty {
            exitSplitKeeping(pane: .left)
        }
    }

    private func exitSplitKeeping(pane: SplitPane) {
        let ids = pane == .left ? splitLeftTabIDs : splitRightTabIDs
        let idx = pane == .left ? splitLeftActiveIdx : splitRightActiveIdx
        guard !ids.isEmpty else {
            splitModeEnabled = false
            splitLeftTabIDs = []
            splitRightTabIDs = []
            splitLeftActiveIdx = 0
            splitRightActiveIdx = 0
            splitPaneFraction = 0.5
            return
        }
        let safeIdx = min(max(0, idx), ids.count - 1)
        let sel = ids[safeIdx]
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            splitModeEnabled = false
            splitLeftTabIDs = []
            splitRightTabIDs = []
            splitLeftActiveIdx = 0
            splitRightActiveIdx = 0
            focusedSplitPane = .left
            splitPaneFraction = 0.5
        }
        browserWorkspace.selectTab(sel)
        focusedAddressBarTabID = nil
    }

    private func normalizeSplitState() {
        guard splitModeEnabled else { return }

        let allBrowserTabIDs = Set(browserWorkspace.tabs.map(\.id))
        splitLeftTabIDs.removeAll { !allBrowserTabIDs.contains($0) }
        splitRightTabIDs.removeAll { !allBrowserTabIDs.contains($0) }

        if !splitLeftTabIDs.isEmpty {
            splitLeftActiveIdx = min(max(0, splitLeftActiveIdx), splitLeftTabIDs.count - 1)
        }
        if !splitRightTabIDs.isEmpty {
            splitRightActiveIdx = min(max(0, splitRightActiveIdx), splitRightTabIDs.count - 1)
        }

        if splitLeftTabIDs.isEmpty, splitRightTabIDs.isEmpty {
            splitModeEnabled = false
            focusedSplitPane = .left
            splitPaneFraction = 0.5
            return
        }
        if splitLeftTabIDs.isEmpty || splitRightTabIDs.isEmpty {
            exitSplitKeepingNonEmptyPane()
        }
    }

    // MARK: Global navigation sync

    private func syncGlobalNavigation() {
        if splitModeEnabled {
            var embedded: Set<RootTabSelection> = []
            if let id = activeTabIDForPane(.left), let t = tab(for: id) {
                embedded.insert(visualPage(for: t).rootTab)
            }
            if let id = activeTabIDForPane(.right), let t = tab(for: id) {
                embedded.insert(visualPage(for: t).rootTab)
            }
            navigationState.browserSplitEmbeddedRootTabs = embedded
        } else {
            navigationState.browserSplitEmbeddedRootTabs = []
        }

        let page = activeVisualPage
        navigationState.selectedRootTab = page.rootTab
        navigationState.selectedView = page.stripTitle

        switch page {
        case .mindfulnessRealm, .pathfinder, .journal, .sleep, .stress:
            navigationState.appFocus = .mentalHealth
        case .search:
            break
        default:
            navigationState.appFocus = .fitness
        }
    }

    private var activeVisualPage: BrowserPageID {
        visualPage(for: tab(for: activeTabID()) ?? browserWorkspace.selectedTab())
    }

    /// Resolved “visual” page for theming (search tab uses top search hit when typing).
    private func visualPage(for tab: BrowserTabSession?) -> BrowserPageID {
        guard let selected = tab else { return .search }
        if selected.currentPage == .search {
            let query = selected.query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty, let first = searchResults(for: query).first {
                return first.page
            }
        }
        return selected.currentPage
    }

    // MARK: Theming

    private func themeColor(for page: BrowserPageID) -> Color {
        switch page {
        case .search: return .cyan
        case .programBuilder: return .orange
        case .dashboard: return .orange
        case .todaysPlan: return .mint
        case .trainingCalendar: return .orange
        case .workoutHistory: return .orange
        case .recoveryScore: return .green
        case .readiness: return .cyan
        case .strainRecovery: return .orange
        case .pastQuests: return .yellow
        case .heartZones: return .red
        case .nutrivanceLabs: return .orange
        case .mindfulnessRealm: return .purple
        case .pathfinder: return .mint
        case .journal: return .indigo
        case .sleep: return .indigo
        case .stress: return .red
        }
    }

    private var activeThemeColor: Color {
        themeColor(for: activeVisualPage)
    }

    @ViewBuilder
    private var activeBackgroundGradient: some View {
        if splitModeEnabled {
            let leftPage = visualPage(for: activeTabIDForPane(.left).flatMap { tab(for: $0) })
            let rightPage = visualPage(for: activeTabIDForPane(.right).flatMap { tab(for: $0) })
            let f = min(Self.splitMaxPaneFraction, max(Self.splitMinPaneFraction, splitPaneFraction))
            GeometryReader { geo in
                let w = geo.size.width
                let leftW = w * f
                let rightW = w - leftW
                Group {
                    if isSplitResizeDragging {
                        HStack(spacing: 0) {
                            themeColor(for: leftPage)
                                .opacity(0.42)
                                .frame(width: leftW, height: geo.size.height)
                            themeColor(for: rightPage)
                                .opacity(0.42)
                                .frame(width: rightW, height: geo.size.height)
                        }
                    } else {
                        HStack(spacing: 0) {
                            meshBackgroundGradient(for: leftPage)
                                .frame(width: leftW, height: geo.size.height, alignment: .leading)
                                .clipped()
                            meshBackgroundGradient(for: rightPage)
                                .frame(width: rightW, height: geo.size.height, alignment: .trailing)
                                .clipped()
                        }
                    }
                }
                .frame(width: w, height: geo.size.height)
            }
            .ignoresSafeArea()
        } else {
            meshBackgroundGradient(for: activeVisualPage)
        }
    }

    @ViewBuilder
    private func meshBackgroundGradient(for page: BrowserPageID) -> some View {
        let gradients = GradientBackgrounds()
        switch page {
        case .search:
            gradients.kineticPulseGradient(animationPhase: $animationPhase)
        case .programBuilder:
            gradients.programBuilderGradient(animationPhase: $animationPhase)
        case .dashboard:
            gradients.burningGradient(animationPhase: $animationPhase)
        case .todaysPlan:
            gradients.natureGradient(animationPhase: $animationPhase)
        case .trainingCalendar:
            gradients.burningGradient(animationPhase: $animationPhase)
        case .workoutHistory:
            gradients.burningGradient(animationPhase: $animationPhase)
        case .recoveryScore:
            gradients.forestGradient(animationPhase: $animationPhase)
        case .readiness:
            gradients.oxygenFlowGradient(animationPhase: $animationPhase)
        case .strainRecovery:
            gradients.burningGradient(animationPhase: $animationPhase)
        case .pastQuests:
            gradients.boldGradient(animationPhase: $animationPhase)
        case .heartZones:
            gradients.boldGradient(animationPhase: $animationPhase)
        case .nutrivanceLabs:
            gradients.programBuilderMeshBackground()
        case .mindfulnessRealm:
            gradients.realmGradient(animationPhase: $animationPhase)
        case .pathfinder:
            gradients.spiritGradient(animationPhase: $animationPhase)
        case .journal:
            gradients.spiritGradient(animationPhase: $animationPhase)
        case .sleep:
            gradients.sleepGradient(animationPhase: $animationPhase)
        case .stress:
            gradients.boldGradient(animationPhase: $animationPhase)
        case .nutrivanceLabs:
            gradients.programBuilderGradient(animationPhase: $animationPhase)
        }
    }
}

// MARK: - Full screen page (⌘⇧F)

private struct BrowserFullscreenShell: View {
    let page: BrowserPageID
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            BrowserPageHost(page: page)
                .navigationTitle(page.stripTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done", action: onDismiss)
                        #if targetEnvironment(macCatalyst)
                            .keyboardShortcut(.escape, modifiers: [])
                        #endif
                    }
                }
        }
#if canImport(UIKit)
        .background(BrowserKeyCommandCaptureView())
#endif
    }
}

// MARK: - Open Quickly (⌘⇧O)

#if targetEnvironment(macCatalyst)
private struct BrowserFavoriteSlotKeyCommandsModifier: ViewModifier {
    let onSlot: (Int) -> Void

    func body(content: Content) -> some View {
        content
            .onKeyPress(KeyEquivalent("1"), phases: .down) { p in slotPress(p, 0) }
            .onKeyPress(KeyEquivalent("2"), phases: .down) { p in slotPress(p, 1) }
            .onKeyPress(KeyEquivalent("3"), phases: .down) { p in slotPress(p, 2) }
            .onKeyPress(KeyEquivalent("4"), phases: .down) { p in slotPress(p, 3) }
            .onKeyPress(KeyEquivalent("5"), phases: .down) { p in slotPress(p, 4) }
            .onKeyPress(KeyEquivalent("6"), phases: .down) { p in slotPress(p, 5) }
            .onKeyPress(KeyEquivalent("7"), phases: .down) { p in slotPress(p, 6) }
            .onKeyPress(KeyEquivalent("8"), phases: .down) { p in slotPress(p, 7) }
            .onKeyPress(KeyEquivalent("9"), phases: .down) { p in slotPress(p, 8) }
            .onKeyPress(KeyEquivalent("0"), phases: .down) { p in slotPress(p, 9) }
    }

    private func slotPress(_ p: KeyPress, _ index: Int) -> KeyPress.Result {
        guard p.modifiers.contains(.command), p.modifiers.contains(.option) else { return .ignored }
        onSlot(index)
        return .handled
    }
}
#else
private struct BrowserFavoriteSlotKeyCommandsModifier: ViewModifier {
    let onSlot: (Int) -> Void
    func body(content: Content) -> some View { content }
}
#endif

private struct BrowserOpenQuicklyPanel: View {
    @Binding var query: String
    @Binding var selectedIndex: Int
    @Binding var isFocused: Bool
    @FocusState private var isFieldFocused: Bool
    let matches: [BrowserSearchResult]
    let onPick: (BrowserPageID, Bool) -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 0) {
                openQuicklySearchField
                    .padding(.horizontal, 14)
                    .padding(.top, 14)

                if !matches.isEmpty {
                    Divider()
                        .opacity(0.35)
                        .padding(.horizontal, 18)
                        .padding(.top, 12)

                    Text("Results")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 22)
                        .padding(.top, 10)
                        .padding(.bottom, 4)

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(matches.enumerated()), id: \.element.id) { index, result in
                                    Button {
                                        onPick(result.page, false)
                                    } label: {
                                        openQuicklyRow(
                                            symbol: result.symbol,
                                            title: result.title,
                                            subtitle: "Nutrivance › \(result.title)",
                                            isSelected: index == selectedIndex
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .id(result.page)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.bottom, 10)
                        }
                        .frame(maxHeight: min(CGFloat(matches.count) * 56 + 16, 320))
                        .onChange(of: selectedIndex) { _, newIdx in
                            guard newIdx < matches.count else { return }
                            withAnimation(.easeInOut(duration: 0.15)) {
                                proxy.scrollTo(matches[newIdx].page, anchor: .center)
                            }
                        }
                    }
                } else {
                    Spacer(minLength: 0)
                        .frame(height: 8)
                }
            }
            .frame(maxWidth: 540)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.regularMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.22), Color.primary.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: Color.black.opacity(0.35), radius: 28, y: 14)
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
        .onKeyPress(.escape, phases: .down) { _ in
            onCancel()
            return .handled
        }
        .onKeyPress(.upArrow, phases: .down) { _ in
            guard !matches.isEmpty else { return .ignored }
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow, phases: .down) { _ in
            guard !matches.isEmpty else { return .ignored }
            selectedIndex = min(matches.count - 1, selectedIndex + 1)
            return .handled
        }
        .onKeyPress(.return, phases: .down) { press in
            guard selectedIndex < matches.count else { return .ignored }
            let optionHeld = press.modifiers.contains(.option)
            confirmSelection(optionHeld: optionHeld)
            return .handled
        }
    }

    private func confirmSelection(optionHeld: Bool) {
        guard selectedIndex < matches.count else { return }
        onPick(matches[selectedIndex].page, optionHeld)
    }

    private func openQuicklyRow(symbol: String, title: String, subtitle: String, isSelected: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .frame(width: 30, height: 30)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Color.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
        }
        .contentShape(Rectangle())
    }

    private var openQuicklySearchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
            TextField("Open Quickly", text: $query)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isFieldFocused)
                .submitLabel(.go)
                .onSubmit {
                    if selectedIndex < matches.count {
                        onPick(matches[selectedIndex].page, false)
                    }
                }
            Image(systemName: "rectangle.on.rectangle")
                .font(.body)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background {
            Capsule(style: .continuous)
                .fill(.thickMaterial)
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .onChange(of: isFocused) { _, newValue in
            isFieldFocused = newValue
        }
    }
}

// MARK: - Browser supporting views

private struct BrowserAllTabsGridView: View {
    @Environment(\.dismiss) private var dismiss
    let tabs: [BrowserTabSession]
    let selectedTabID: UUID
    let onSelect: (UUID) -> Void
    let onClose: (UUID) -> Void

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(tabs) { tab in
                        Button {
                            onSelect(tab.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Label(tab.currentPage.stripTitle, systemImage: tab.currentPage.symbol)
                                        .font(.caption.weight(.semibold))
                                    Spacer()
                                    Button {
                                        onClose(tab.id)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                Text(tab.currentPage == .search ? BrowserPageID.search.stripTitle : tab.currentPage.stripTitle)
                                    .font(.headline)
                                    .lineLimit(2)
                                Text(tab.query.isEmpty ? "No search query" : tab.query)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                selectedTabID == tab.id
                                    ? Color.accentColor.opacity(0.22)
                                    : Color.white.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(selectedTabID == tab.id ? Color.accentColor.opacity(0.55) : Color.white.opacity(0.1), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .catalystDesktopFocusable()
                    }
                }
                .padding()
            }
            .navigationTitle("All Tabs")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - UIKit (window scene & key commands)

#if canImport(UIKit)
private struct WindowSceneResolver: UIViewControllerRepresentable {
    var onResolve: (UIWindowScene?) -> Void

    final class Coordinator: NSObject {
        weak var lastNotifiedScene: UIWindowScene?
        var didScheduleNilWindowRetry = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        resolve(from: uiViewController, coordinator: context.coordinator)
    }

    private func resolve(from vc: UIViewController, coordinator: Coordinator) {
        if let scene = vc.view.window?.windowScene {
            if coordinator.lastNotifiedScene !== scene {
                coordinator.lastNotifiedScene = scene
                onResolve(scene)
            }
            coordinator.didScheduleNilWindowRetry = false
            return
        }

        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let owningScene = scenes.first(where: { scene in
            scene.windows.contains { window in
                var current: UIView? = vc.view
                while let view = current {
                    if view === window {
                        return true
                    }
                    current = view.superview
                }
                return false
            }
        }) {
            if coordinator.lastNotifiedScene !== owningScene {
                coordinator.lastNotifiedScene = owningScene
                onResolve(owningScene)
            }
            coordinator.didScheduleNilWindowRetry = false
            return
        }

        if !coordinator.didScheduleNilWindowRetry {
            coordinator.didScheduleNilWindowRetry = true
            DispatchQueue.main.async { [weak vc] in
                coordinator.didScheduleNilWindowRetry = false
                guard let vc else { return }
                resolve(from: vc, coordinator: coordinator)
            }
        }
    }
}

private struct BrowserKeyCommandCaptureView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> BrowserKeyCommandCaptureController {
        BrowserKeyCommandCaptureController()
    }

    func updateUIViewController(_ uiViewController: BrowserKeyCommandCaptureController, context: Context) {
        uiViewController.refreshFirstResponder()
    }
}

private final class BrowserKeyCommandCaptureController: UIViewController {
    override var canBecomeFirstResponder: Bool { true }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        // Disable the default window-close responder action so Cmd+W is owned by browser tab closing.
        if action == Selector(("performClose:")) {
            return false
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override var keyCommands: [UIKeyCommand]? {
        let newTabCommand = UIKeyCommand(input: "t", modifierFlags: [.command], action: #selector(newTab))
        newTabCommand.wantsPriorityOverSystemBehavior = true

        let closeTabCommand = UIKeyCommand(input: "w", modifierFlags: [.command], action: #selector(closeTab))
        closeTabCommand.wantsPriorityOverSystemBehavior = true

        let closeOtherTabsCommand = UIKeyCommand(input: "w", modifierFlags: [.command, .alternate], action: #selector(closeOtherTabs))
        closeOtherTabsCommand.wantsPriorityOverSystemBehavior = true

        let closeWindowCommand = UIKeyCommand(input: "w", modifierFlags: [.command, .shift], action: #selector(closeWindow))
        closeWindowCommand.wantsPriorityOverSystemBehavior = true

        let splitLeftCommand = UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [.command, .control], action: #selector(splitLeft))
        splitLeftCommand.wantsPriorityOverSystemBehavior = true

        let splitRightCommand = UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [.command, .control], action: #selector(splitRight))
        splitRightCommand.wantsPriorityOverSystemBehavior = true

        let swapSplitCommand = UIKeyCommand(input: "\\", modifierFlags: [.command, .control], action: #selector(swapSplit))
        swapSplitCommand.wantsPriorityOverSystemBehavior = true

        let cyclePrevTabInPaneCommand = UIKeyCommand(input: "[", modifierFlags: [.command, .shift], action: #selector(cyclePrevTabInPane))
        cyclePrevTabInPaneCommand.wantsPriorityOverSystemBehavior = true

        let cycleNextTabInPaneCommand = UIKeyCommand(input: "]", modifierFlags: [.command, .shift], action: #selector(cycleNextTabInPane))
        cycleNextTabInPaneCommand.wantsPriorityOverSystemBehavior = true

        let cyclePrevTabGloballyCommand = UIKeyCommand(input: "[", modifierFlags: [.command, .control], action: #selector(cyclePrevTabGlobally))
        cyclePrevTabGloballyCommand.wantsPriorityOverSystemBehavior = true

        let cycleNextTabGloballyCommand = UIKeyCommand(input: "]", modifierFlags: [.command, .control], action: #selector(cycleNextTabGlobally))
        cycleNextTabGloballyCommand.wantsPriorityOverSystemBehavior = true

        let cycleSplitPaneFwd = UIKeyCommand(input: "\t", modifierFlags: .control, action: #selector(cycleSplitPaneForward))
        cycleSplitPaneFwd.wantsPriorityOverSystemBehavior = true

        let cycleSplitPaneRev = UIKeyCommand(input: "\t", modifierFlags: [.control, .shift], action: #selector(cycleSplitPaneReverse))
        cycleSplitPaneRev.wantsPriorityOverSystemBehavior = true

        let openQuicklyCommand = UIKeyCommand(input: "o", modifierFlags: [.command, .shift], action: #selector(openBrowserQuickly))
        openQuicklyCommand.wantsPriorityOverSystemBehavior = true

        let toggleFullscreenCommand = UIKeyCommand(input: "f", modifierFlags: [.command, .shift], action: #selector(toggleFullscreen))
        toggleFullscreenCommand.wantsPriorityOverSystemBehavior = true

        let focusAddressBarCommand = UIKeyCommand(input: "l", modifierFlags: [.command], action: #selector(focusAddressBar))
        focusAddressBarCommand.wantsPriorityOverSystemBehavior = true

        let bf1 = UIKeyCommand(input: "1", modifierFlags: [.command, .alternate], action: #selector(browserFavoriteShortcut1))
        bf1.wantsPriorityOverSystemBehavior = true
        let bf2 = UIKeyCommand(input: "2", modifierFlags: [.command, .alternate], action: #selector(browserFavoriteShortcut2))
        bf2.wantsPriorityOverSystemBehavior = true
        let bf3 = UIKeyCommand(input: "3", modifierFlags: [.command, .alternate], action: #selector(browserFavoriteShortcut3))
        bf3.wantsPriorityOverSystemBehavior = true
        let bf4 = UIKeyCommand(input: "4", modifierFlags: [.command, .alternate], action: #selector(browserFavoriteShortcut4))
        bf4.wantsPriorityOverSystemBehavior = true
        let bf5 = UIKeyCommand(input: "5", modifierFlags: [.command, .alternate], action: #selector(browserFavoriteShortcut5))
        bf5.wantsPriorityOverSystemBehavior = true
        let bf6 = UIKeyCommand(input: "6", modifierFlags: [.command, .alternate], action: #selector(browserFavoriteShortcut6))
        bf6.wantsPriorityOverSystemBehavior = true
        let bf7 = UIKeyCommand(input: "7", modifierFlags: [.command, .alternate], action: #selector(browserFavoriteShortcut7))
        bf7.wantsPriorityOverSystemBehavior = true
        let bf8 = UIKeyCommand(input: "8", modifierFlags: [.command, .alternate], action: #selector(browserFavoriteShortcut8))
        bf8.wantsPriorityOverSystemBehavior = true
        let bf9 = UIKeyCommand(input: "9", modifierFlags: [.command, .alternate], action: #selector(browserFavoriteShortcut9))
        bf9.wantsPriorityOverSystemBehavior = true
        let bf0 = UIKeyCommand(input: "0", modifierFlags: [.command, .alternate], action: #selector(browserFavoriteShortcut0))
        bf0.wantsPriorityOverSystemBehavior = true

        let calendarPrevDayCommand = UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [.command], action: #selector(calendarPreviousDay))
        calendarPrevDayCommand.wantsPriorityOverSystemBehavior = true

        let calendarNextDayCommand = UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [.command], action: #selector(calendarNextDay))
        calendarNextDayCommand.wantsPriorityOverSystemBehavior = true

        let calendarPrevMonthCommand = UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [.command, .alternate], action: #selector(calendarPreviousMonth))
        calendarPrevMonthCommand.wantsPriorityOverSystemBehavior = true

        let calendarNextMonthCommand = UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [.command, .alternate], action: #selector(calendarNextMonth))
        calendarNextMonthCommand.wantsPriorityOverSystemBehavior = true

        let calendarRefreshCommand = UIKeyCommand(input: "r", modifierFlags: [.command], action: #selector(calendarRefresh))
        calendarRefreshCommand.wantsPriorityOverSystemBehavior = true

        let calendarTodayCommand = UIKeyCommand(input: "t", modifierFlags: [.command, .shift], action: #selector(calendarToday))
        calendarTodayCommand.wantsPriorityOverSystemBehavior = true

        let calendarHRZoneCommand = UIKeyCommand(input: "u", modifierFlags: [.command], action: #selector(calendarHRZone))
        calendarHRZoneCommand.wantsPriorityOverSystemBehavior = true

        let strainFilter1DCommand = UIKeyCommand(input: "1", modifierFlags: [.command], action: #selector(strainFilter1D))
        strainFilter1DCommand.wantsPriorityOverSystemBehavior = true

        let strainFilter1WCommand = UIKeyCommand(input: "2", modifierFlags: [.command], action: #selector(strainFilter1W))
        strainFilter1WCommand.wantsPriorityOverSystemBehavior = true

        let strainFilter1MCommand = UIKeyCommand(input: "3", modifierFlags: [.command], action: #selector(strainFilter1M))
        strainFilter1MCommand.wantsPriorityOverSystemBehavior = true

        let strainTodayCommand = UIKeyCommand(input: "t", modifierFlags: [.command, .shift], action: #selector(strainToday))
        strainTodayCommand.wantsPriorityOverSystemBehavior = true

        let strainUnitSettingsCommand = UIKeyCommand(input: "u", modifierFlags: [.command], action: #selector(strainUnitSettings))
        strainUnitSettingsCommand.wantsPriorityOverSystemBehavior = true

        let strainPreviousCommand = UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [.command], action: #selector(strainPrevious))
        strainPreviousCommand.wantsPriorityOverSystemBehavior = true

        let strainNextCommand = UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [.command], action: #selector(strainNext))
        strainNextCommand.wantsPriorityOverSystemBehavior = true

        return [newTabCommand, closeTabCommand, closeOtherTabsCommand, closeWindowCommand, splitLeftCommand, splitRightCommand, swapSplitCommand, cyclePrevTabInPaneCommand, cycleNextTabInPaneCommand, cyclePrevTabGloballyCommand, cycleNextTabGloballyCommand, cycleSplitPaneFwd, cycleSplitPaneRev, openQuicklyCommand, toggleFullscreenCommand, focusAddressBarCommand, bf1, bf2, bf3, bf4, bf5, bf6, bf7, bf8, bf9, bf0, calendarPrevDayCommand, calendarNextDayCommand, calendarPrevMonthCommand, calendarNextMonthCommand, calendarRefreshCommand, calendarTodayCommand, calendarHRZoneCommand, strainFilter1DCommand, strainFilter1WCommand, strainFilter1MCommand, strainTodayCommand, strainUnitSettingsCommand, strainPreviousCommand, strainNextCommand]
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    func refreshFirstResponder() {
        becomeFirstResponder()
    }

    @objc private func newTab() {
        NotificationCenter.default.post(name: .nutrivanceBrowserNewTab, object: view.window?.windowScene)
    }

    @objc private func closeTab() {
        NotificationCenter.default.post(name: .nutrivanceBrowserCloseTab, object: view.window?.windowScene)
    }

    @objc private func closeOtherTabs() {
        NotificationCenter.default.post(name: .nutrivanceBrowserCloseOtherTabs, object: view.window?.windowScene)
    }

    @objc private func closeWindow() {
        NotificationCenter.default.post(name: .nutrivanceBrowserCloseWindow, object: view.window?.windowScene)
    }

    @objc private func splitLeft() {
        NotificationCenter.default.post(name: .nutrivanceBrowserSplitAssignLeft, object: view.window?.windowScene)
    }

    @objc private func splitRight() {
        NotificationCenter.default.post(name: .nutrivanceBrowserSplitAssignRight, object: view.window?.windowScene)
    }

    @objc private func swapSplit() {
        NotificationCenter.default.post(name: .nutrivanceBrowserSwapSplitPanes, object: view.window?.windowScene)
    }

    @objc private func cyclePrevTabInPane() {
        NotificationCenter.default.post(name: .nutrivanceBrowserCyclePrevTabInPane, object: view.window?.windowScene)
    }

    @objc private func cycleNextTabInPane() {
        NotificationCenter.default.post(name: .nutrivanceBrowserCycleNextTabInPane, object: view.window?.windowScene)
    }

    @objc private func cyclePrevTabGlobally() {
        NotificationCenter.default.post(name: .nutrivanceBrowserCyclePrevTabGlobally, object: view.window?.windowScene)
    }

    @objc private func cycleNextTabGlobally() {
        NotificationCenter.default.post(name: .nutrivanceBrowserCycleNextTabGlobally, object: view.window?.windowScene)
    }

    @objc private func cycleSplitPaneForward() {
        NotificationCenter.default.post(name: .nutrivanceBrowserCycleSplitPaneForward, object: view.window?.windowScene)
    }

    @objc private func cycleSplitPaneReverse() {
        NotificationCenter.default.post(name: .nutrivanceBrowserCycleSplitPaneReverse, object: view.window?.windowScene)
    }

    @objc private func toggleFullscreen() {
        NotificationCenter.default.post(name: .nutrivanceBrowserToggleFullscreen, object: view.window?.windowScene)
    }

    @objc private func openBrowserQuickly() {
        NotificationCenter.default.post(name: .nutrivanceBrowserOpenQuickly, object: view.window?.windowScene)
    }

    private func postFavoriteBrowserSlot(_ index: Int) {
        NotificationCenter.default.post(
            name: .nutrivanceBrowserOpenFavoriteSlot,
            object: view.window?.windowScene,
            userInfo: ["index": index]
        )
    }

    @objc private func browserFavoriteShortcut1() { postFavoriteBrowserSlot(0) }
    @objc private func browserFavoriteShortcut2() { postFavoriteBrowserSlot(1) }
    @objc private func browserFavoriteShortcut3() { postFavoriteBrowserSlot(2) }
    @objc private func browserFavoriteShortcut4() { postFavoriteBrowserSlot(3) }
    @objc private func browserFavoriteShortcut5() { postFavoriteBrowserSlot(4) }
    @objc private func browserFavoriteShortcut6() { postFavoriteBrowserSlot(5) }
    @objc private func browserFavoriteShortcut7() { postFavoriteBrowserSlot(6) }
    @objc private func browserFavoriteShortcut8() { postFavoriteBrowserSlot(7) }
    @objc private func browserFavoriteShortcut9() { postFavoriteBrowserSlot(8) }
    @objc private func browserFavoriteShortcut0() { postFavoriteBrowserSlot(9) }

    @objc private func focusAddressBar() {
        NotificationCenter.default.post(name: .nutrivanceBrowserFocusAddressBar, object: view.window?.windowScene)
    }

    @objc private func calendarPreviousDay() {
        NotificationCenter.default.post(name: .nutrivanceViewControlTrainingCalendarPreviousDay, object: view.window?.windowScene)
    }

    @objc private func calendarNextDay() {
        NotificationCenter.default.post(name: .nutrivanceViewControlTrainingCalendarNextDay, object: view.window?.windowScene)
    }

    @objc private func calendarPreviousMonth() {
        NotificationCenter.default.post(name: .nutrivanceViewControlTrainingCalendarPreviousMonth, object: view.window?.windowScene)
    }

    @objc private func calendarNextMonth() {
        NotificationCenter.default.post(name: .nutrivanceViewControlTrainingCalendarNextMonth, object: view.window?.windowScene)
    }

    @objc private func calendarRefresh() {
        NotificationCenter.default.post(name: .nutrivanceViewControlTrainingCalendarRefresh, object: view.window?.windowScene)
    }

    @objc private func calendarToday() {
        NotificationCenter.default.post(name: .nutrivanceViewControlTrainingCalendarToday, object: view.window?.windowScene)
    }

    @objc private func calendarHRZone() {
        NotificationCenter.default.post(name: .nutrivanceViewControlTrainingCalendarHRZoneSettings, object: view.window?.windowScene)
    }

    @objc private func strainFilter1D() {
        NotificationCenter.default.post(name: .nutrivanceViewControlFilter1, object: view.window?.windowScene)
    }

    @objc private func strainFilter1W() {
        NotificationCenter.default.post(name: .nutrivanceViewControlFilter2, object: view.window?.windowScene)
    }

    @objc private func strainFilter1M() {
        NotificationCenter.default.post(name: .nutrivanceViewControlFilter3, object: view.window?.windowScene)
    }

    @objc private func strainToday() {
        NotificationCenter.default.post(name: .nutrivanceViewControlToday, object: view.window?.windowScene)
    }

    @objc private func strainUnitSettings() {
        NotificationCenter.default.post(name: .nutrivanceViewControlStrainRecoverySettings, object: view.window?.windowScene)
    }

    @objc private func strainPrevious() {
        NotificationCenter.default.post(name: .nutrivanceViewControlPrevious, object: view.window?.windowScene)
    }

    @objc private func strainNext() {
        NotificationCenter.default.post(name: .nutrivanceViewControlNext, object: view.window?.windowScene)
    }
}
#endif

// MARK: - Search catalog & hosted pages

private struct BrowserSearchResult: Identifiable, Hashable {
    let page: BrowserPageID
    let aliases: [String]
    var id: BrowserPageID { page }
    var title: String { page.stripTitle }
    var symbol: String { page.symbol }

    static let catalog: [BrowserSearchResult] = [
        .init(page: .search, aliases: ["find", "lookup", "palette"]),
        .init(page: .programBuilder, aliases: ["builder", "plan", "program"]),
        .init(page: .dashboard, aliases: ["overview", "metrics"]),
        .init(page: .todaysPlan, aliases: ["today", "plan"]),
        .init(page: .trainingCalendar, aliases: ["calendar", "month", "sessions"]),
        .init(page: .workoutHistory, aliases: ["history", "workouts", "log"]),
        .init(page: .recoveryScore, aliases: ["recovery", "score"]),
        .init(page: .readiness, aliases: ["readiness", "check"]),
        .init(page: .strainRecovery, aliases: ["strain", "load", "recovery"]),
        .init(page: .pastQuests, aliases: ["quests", "past", "records"]),
        .init(page: .heartZones, aliases: ["zones", "heart rate", "hr"]),
        .init(page: .nutrivanceLabs, aliases: ["labs", "tuning", "personalization", "nudge"]),
        .init(page: .mindfulnessRealm, aliases: ["mindfulness", "meditation"]),
        .init(page: .pathfinder, aliases: ["pathfinder", "emotion"]),
        .init(page: .journal, aliases: ["journal", "notes"]),
        .init(page: .sleep, aliases: ["sleep", "night"]),
        .init(page: .stress, aliases: ["stress", "hrv"]),
    ]
}

/// Safari-style sheet under the address bar: ranked matches, favorite tiles, widgets, and browse shortcuts.
private struct BrowserAddressBarSuggestionsPanel: View {
    let favorites: [BrowserPageID]
    let widgets: [BrowserHomeWidgetConfig]
    let matches: [BrowserSearchResult]
    let onPickPage: (BrowserPageID) -> Void

    private var quickBrowse: [BrowserSearchResult] {
        let pinned = Set(favorites)
        return BrowserSearchResult.catalog
            .filter { $0.page != .search && !pinned.contains($0.page) }
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !matches.isEmpty {
                    panelSectionTitle("Top hits")
                    VStack(spacing: 8) {
                        ForEach(matches.prefix(8)) { result in
                            suggestionRow(symbol: result.symbol, title: result.title, subtitle: nil) {
                                onPickPage(result.page)
                            }
                        }
                    }
                }

                if !favorites.isEmpty {
                    panelSectionTitle("Favorites")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 14)], spacing: 16) {
                        ForEach(favorites, id: \.self) { page in
                            Button {
                                onPickPage(page)
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: page.symbol)
                                        .font(.title2.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .frame(width: 58, height: 58)
                                        .background {
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .fill(.thinMaterial)
                                        }
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                                        }
                                    Text(page.stripTitle)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .frame(maxWidth: 88)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !widgets.isEmpty {
                    panelSectionTitle("Quick actions")
                    VStack(spacing: 10) {
                        ForEach(widgets) { widget in
                            Button {
                                onPickPage(widget.page)
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: widget.page.symbol)
                                        .font(.title3)
                                        .frame(width: 44, height: 44)
                                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(widget.title)
                                            .font(.subheadline.weight(.semibold))
                                        Text(widget.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(12)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                panelSectionTitle("Browse")
                VStack(spacing: 8) {
                    ForEach(quickBrowse) { result in
                        suggestionRow(symbol: result.symbol, title: result.title, subtitle: "Open \(result.title)") {
                            onPickPage(result.page)
                        }
                    }
                }
            }
            .padding(20)
        }
        .frame(maxHeight: 460)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.28), radius: 32, x: 0, y: 18)
    }

    private func panelSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.6)
    }

    private func suggestionRow(symbol: String, title: String, subtitle: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.forward")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct BrowserSearchHomeView: View {
    let favorites: [BrowserPageID]
    let widgets: [BrowserHomeWidgetConfig]
    @Binding var query: String
    let results: [BrowserSearchResult]
    let onPickPage: (BrowserPageID) -> Void

    @FocusState private var startPageSearchFocused: Bool

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Start Page")
                        .font(.largeTitle.bold())
                    Text("Jump anywhere, favorites, and quick actions — customize from the toolbar.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Find a view or command", text: $query)
                        .textFieldStyle(.plain)
                        .focused($startPageSearchFocused)
                        .submitLabel(.search)
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .catalystDesktopFocusable()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )

                if trimmedQuery.isEmpty {
                    sectionTitle("Favorites")
                    Text("First ten favorites: ⌘⌥1 … ⌘⌥9, ⌘⌥0")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: UIDevice.current.userInterfaceIdiom == .pad ? 200 : 140), spacing: 16)],
                        spacing: 24
                    ) {
                        ForEach(Array(favorites.enumerated()), id: \.element) { index, page in
                            Button {
                                onPickPage(page)
                            } label: {
                                startPageExplorerCard(
                                    title: page.stripTitle,
                                    symbol: page.symbol,
                                    slotLabel: favoriteSlotShortcutLabel(zeroBased: index)
                                )
                            }
                            .buttonStyle(.plain)
                            .browserStartPageCardFocusable()
                            .catalystFocusablePrimaryAction {
                                onPickPage(page)
                            }
                        }
                    }

                    if !widgets.isEmpty {
                        sectionTitle("Quick actions")
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: UIDevice.current.userInterfaceIdiom == .pad ? 200 : 140), spacing: 16)],
                            spacing: 24
                        ) {
                            ForEach(widgets) { widget in
                                Button {
                                    onPickPage(widget.page)
                                } label: {
                                    startPageExplorerCard(
                                        title: widget.title,
                                        symbol: widget.page.symbol,
                                        subtitle: widget.subtitle,
                                        slotLabel: nil
                                    )
                                }
                                .buttonStyle(.plain)
                                .browserStartPageCardFocusable()
                                .catalystFocusablePrimaryAction {
                                    onPickPage(widget.page)
                                }
                            }
                        }
                    }
                } else {
                    sectionTitle("Results")
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: UIDevice.current.userInterfaceIdiom == .pad ? 200 : 140), spacing: 16)],
                        spacing: 24
                    ) {
                        ForEach(results) { result in
                            Button {
                                onPickPage(result.page)
                            } label: {
                                startPageExplorerCard(
                                    title: result.title,
                                    symbol: result.symbol,
                                    subtitle: "Nutrivance › \(result.title)",
                                    slotLabel: nil
                                )
                            }
                            .buttonStyle(.plain)
                            .browserStartPageCardFocusable()
                            .catalystFocusablePrimaryAction {
                                onPickPage(result.page)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
    }

    private func favoriteSlotShortcutLabel(zeroBased index: Int) -> String? {
        guard index < 10 else { return nil }
        if index <= 8 { return "⌘⌥\(index + 1)" }
        return "⌘⌥0"
    }

    /// Matches the large icon + caption card grid used in `SearchView`.
    private func startPageExplorerCard(title: String, symbol: String, subtitle: String? = nil, slotLabel: String?) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 36))
                .foregroundStyle(.primary)
                .frame(width: 76, height: 76)
                .background(.ultraThinMaterial)
                .clipShape(Circle())

            Text(title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(minHeight: 36)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            if let slotLabel {
                Text(slotLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 120)
        .frame(minHeight: 140)
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
    }
}

private struct BrowserSearchHomeCustomizeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var favorites: [BrowserPageID]
    @Binding var widgets: [BrowserHomeWidgetConfig]
    var onCommit: () -> Void

    private var pagesAvailableToAdd: [BrowserPageID] {
        BrowserPageID.allCases.filter { $0 != .search && !favorites.contains($0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Order favorites with Edit. The first ten map to ⌘⌥1 through ⌘⌥9, then ⌘⌥0.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Favorites") {
                    ForEach(favorites, id: \.self) { page in
                        Label(page.stripTitle, systemImage: page.symbol)
                    }
                    .onMove { from, to in
                        favorites.move(fromOffsets: from, toOffset: to)
                    }
                    .onDelete { favorites.remove(atOffsets: $0) }
                }

                if !pagesAvailableToAdd.isEmpty {
                    Section("Add to favorites") {
                        ForEach(pagesAvailableToAdd, id: \.self) { page in
                            Button {
                                favorites.append(page)
                            } label: {
                                Label(page.stripTitle, systemImage: page.symbol)
                            }
                        }
                    }
                }

                Section("Quick actions") {
                    ForEach(widgets) { widget in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(widget.title)
                                Text(widget.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(widget.page.title).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        widgets.remove(atOffsets: offsets)
                    }

                    Menu("Add Widget") {
                        ForEach(BrowserPageID.allCases.filter { $0 != .search }, id: \.self) { page in
                            Button(page.title) {
                                widgets.append(
                                    BrowserHomeWidgetConfig(
                                        title: page.title,
                                        subtitle: "Quick open \(page.title)",
                                        page: page
                                    )
                                )
                            }
                        }
                    }
                }
            }
            .navigationTitle("Customize Start Page")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onCommit()
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct BrowserPageHost: View {
    let page: BrowserPageID

    var body: some View {
        Group {
            switch page {
            case .search:
                SearchView()
            case .programBuilder:
                ProgramBuilderView()
            case .dashboard:
                DashboardView()
            case .todaysPlan:
                TodaysPlanView(planType: .all)
            case .trainingCalendar:
                TrainingCalendarView()
            case .workoutHistory:
                WorkoutHistoryView()
            case .recoveryScore:
                RecoveryScoreView()
            case .readiness:
                ReadinessCheckView()
            case .strainRecovery:
                StrainRecoveryView()
            case .pastQuests:
                PastQuestsView()
            case .heartZones:
                HeartZonesView()
            case .nutrivanceLabs:
                NutrivanceLabsView()
            case .mindfulnessRealm:
                MindfulnessRealmView()
            case .pathfinder:
                PathfinderView()
            case .journal:
                JournalView()
            case .sleep:
                SleepView()
            case .stress:
                StressView()
            case .nutrivanceLabs:
                NutrivanceLabsView()
            }
        }
    }
}
