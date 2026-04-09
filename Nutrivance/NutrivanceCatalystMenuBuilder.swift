import UIKit

// Shared by **Mac Catalyst** and **iPad** (desktop-class menu bar). SwiftUI `CommandMenu` is unreliable on iPad;
// UIKit `UIMenuBuilder` + `UIKeyCommand` is what actually appears next to File / Edit / View.

// MARK: - Responder-chain targets (UIApplication is always in the chain)

extension UIApplication {
    @objc(nutrivanceCatalystOpenNewWindow:)
    func nutrivanceCatalystOpenNewWindow(_ sender: Any?) {
        #if targetEnvironment(macCatalyst)
        requestSceneSessionActivation(nil, userActivity: nil, options: nil, errorHandler: nil)
        #endif
    }

    @objc(nutrivanceCatalystMainMenuCommand:)
    func nutrivanceCatalystMainMenuCommand(_ sender: Any?) {
        guard let command = sender as? UICommand,
              let key = command.propertyList as? String else { return }
        NutrivanceSceneMenuRouter.postMainMenuCommand(key)
    }

    @objc(nutrivanceCatalystPostNotification:)
    func nutrivanceCatalystPostNotification(_ sender: Any?) {
        guard let command = sender as? UICommand,
              let raw = command.propertyList as? String else { return }
        NotificationCenter.default.post(name: Notification.Name(rawValue: raw), object: nil)
    }

    @objc(nutrivanceCatalystPostNotificationForActiveScene:)
    func nutrivanceCatalystPostNotificationForActiveScene(_ sender: Any?) {
        guard let command = sender as? UICommand,
              let raw = command.propertyList as? String else { return }
        let targetScenePersistentIdentifier = NutrivanceSceneMenuRouter.targetScenePersistentIdentifierForMenuCommand()
        NotificationCenter.default.post(
            name: Notification.Name(rawValue: raw),
            object: targetScenePersistentIdentifier
        )
    }

    @objc(nutrivanceCatalystHeartZonesSportSlot:)
    func nutrivanceCatalystHeartZonesSportSlot(_ sender: Any?) {
        guard let command = sender as? UICommand,
              let number = command.propertyList as? NSNumber else { return }
        let targetScenePersistentIdentifier = NutrivanceSceneMenuRouter.targetScenePersistentIdentifierForMenuCommand()
        NotificationCenter.default.post(
            name: .nutrivanceViewControlHeartZonesSportSlot,
            object: targetScenePersistentIdentifier,
            userInfo: ["slot": number.intValue]
        )
    }

    @objc(nutrivanceCatalystNoOpMenuAction:)
    func nutrivanceCatalystNoOpMenuAction(_ sender: Any?) {}
}

// MARK: - Main menu (reliable on Catalyst; SwiftUI CommandMenu often does not appear)

enum NutrivanceCatalystMenuBuilder {
    private static let navSelector = #selector(UIApplication.nutrivanceCatalystMainMenuCommand(_:))
    private static let postSceneSelector = #selector(UIApplication.nutrivanceCatalystPostNotificationForActiveScene(_:))
    private static let openWindowSelector = #selector(UIApplication.nutrivanceCatalystOpenNewWindow(_:))
    private static let hzSlotSelector = #selector(UIApplication.nutrivanceCatalystHeartZonesSportSlot(_:))
    private static let noOpSelector = #selector(UIApplication.nutrivanceCatalystNoOpMenuAction(_:))

    // Mirrors `NutrivanceApp` SwiftUI `.keyboardShortcut` (iPad); `UIKeyCommand` shows keys in the Catalyst menu bar.
    private static func navKey(_ title: String, input: String, _ modifiers: UIKeyModifierFlags, plist: String) -> UIKeyCommand {
        UIKeyCommand(title: title, action: navSelector, input: input, modifierFlags: modifiers, propertyList: plist)
    }

    private static func vcKey(_ title: String, _ name: Notification.Name, input: String, _ modifiers: UIKeyModifierFlags) -> UIKeyCommand {
        UIKeyCommand(title: title, action: postSceneSelector, input: input, modifierFlags: modifiers, propertyList: name.rawValue)
    }

    private static func hzKey(_ title: String, slot: Int, input: String, _ modifiers: UIKeyModifierFlags) -> UIKeyCommand {
        UIKeyCommand(title: title, action: hzSlotSelector, input: input, modifierFlags: modifiers, propertyList: NSNumber(value: slot))
    }

    private static let cmd = UIKeyModifierFlags.command
    private static let cmdShift: UIKeyModifierFlags = [.command, .shift]
    private static let cmdOpt: UIKeyModifierFlags = [.command, .alternate]
    private static let opt: UIKeyModifierFlags = [.alternate]

    static func augmentMainMenu(with builder: UIMenuBuilder) {
        replaceFileAndWindowMenus(with: builder)

        let navigation = UIMenu(
            title: "Navigation",
            identifier: UIMenu.Identifier("com.nutrivance.menu.navigation"),
            options: [],
            children: [
                // Matches `NutrivanceApp` / system back: ⌘[ (not ⌘⇧[).
                navKey("Back", input: "[", cmd, plist: "back"),
                navKey("Program Builder", input: "b", cmdShift, plist: "programBuilder"),
                navKey("Dashboard", input: "d", cmdShift, plist: "dashboard"),
                navKey("Mindfulness Realm", input: "r", cmdShift, plist: "mindfulnessRealm"),
                navKey("Today's Plan", input: "p", cmdShift, plist: "todaysPlan"),
                navKey("Training Calendar", input: "c", cmdShift, plist: "trainingCalendar"),
                navKey("Workout History", input: "h", cmdShift, plist: "workoutHistory"),
                navKey("Recovery Score", input: "y", cmdShift, plist: "recoveryScore"),
                navKey("Readiness Score", input: "i", cmdShift, plist: "readiness"),
                navKey("Strain vs Recovery", input: "v", cmdShift, plist: "strainRecovery"),
                navKey("Past Quests", input: "u", cmdShift, plist: "pastQuests"),
                navKey("Heart Zones", input: "z", cmdShift, plist: "heartZones"),
                navKey("Pathfinder", input: "k", cmdShift, plist: "pathfinder"),
                navKey("Journal", input: "j", cmdShift, plist: "journal"),
                navKey("Sleep", input: "l", cmdShift, plist: "sleep"),
                navKey("Stress", input: "t", cmdShift, plist: "stress")
            ]
        )

        let search = UIMenu(
            title: "Search",
            identifier: UIMenu.Identifier("com.nutrivance.menu.search"),
            options: [],
            children: [
                navKey("Find", input: "f", cmd, plist: "find")
            ]
        )

        let viewControlsDeferred = UIDeferredMenuElement { completion in
            DispatchQueue.main.async {
                completion(Self.makeViewControlElements())
            }
        }
        let viewControls = UIMenu(
            title: "View Controls",
            identifier: UIMenu.Identifier("com.nutrivance.menu.viewControls"),
            options: [],
            children: [viewControlsDeferred]
        )

        builder.insertSibling(navigation, afterMenu: .view)
        builder.insertSibling(search, afterMenu: UIMenu.Identifier("com.nutrivance.menu.navigation"))
        builder.insertSibling(viewControls, afterMenu: UIMenu.Identifier("com.nutrivance.menu.search"))
    }

    private static func replaceFileAndWindowMenus(with builder: UIMenuBuilder) {
        let fileElements: [UIMenuElement] = [
            UIKeyCommand(title: "New Window", action: openWindowSelector, input: "n", modifierFlags: cmd),
            UIKeyCommand(title: "New Tab", action: postSceneSelector, input: "t", modifierFlags: cmd, propertyList: Notification.Name.nutrivanceBrowserNewTab.rawValue),
            UIKeyCommand(title: "Close Tab", action: postSceneSelector, input: "w", modifierFlags: cmd, propertyList: Notification.Name.nutrivanceBrowserCloseTab.rawValue),
            UIKeyCommand(title: "Close Other Tabs", action: postSceneSelector, input: "w", modifierFlags: cmdOpt, propertyList: Notification.Name.nutrivanceBrowserCloseOtherTabs.rawValue),
            UIKeyCommand(title: "Close Window", action: postSceneSelector, input: "w", modifierFlags: cmdShift, propertyList: Notification.Name.nutrivanceBrowserCloseWindow.rawValue),
            UIKeyCommand(title: "Split Focused Tab to Left", action: postSceneSelector, input: UIKeyCommand.inputLeftArrow, modifierFlags: [.command, .control], propertyList: Notification.Name.nutrivanceBrowserSplitAssignLeft.rawValue),
            UIKeyCommand(title: "Split Focused Tab to Right", action: postSceneSelector, input: UIKeyCommand.inputRightArrow, modifierFlags: [.command, .control], propertyList: Notification.Name.nutrivanceBrowserSplitAssignRight.rawValue),
            UIKeyCommand(title: "Swap with Last Interacted Tab", action: postSceneSelector, input: UIKeyCommand.inputLeftArrow, modifierFlags: [.command, .control, .shift], propertyList: Notification.Name.nutrivanceBrowserSwapWithLastInteracted.rawValue),
            UIKeyCommand(title: "Open Quickly", action: postSceneSelector, input: "o", modifierFlags: cmdShift, propertyList: Notification.Name.nutrivanceBrowserOpenQuickly.rawValue),
            UIKeyCommand(title: "Full Screen Page", action: postSceneSelector, input: "f", modifierFlags: cmdShift, propertyList: Notification.Name.nutrivanceBrowserToggleFullscreen.rawValue),
            UIKeyCommand(title: "Focus Address Bar", action: postSceneSelector, input: "l", modifierFlags: cmd, propertyList: Notification.Name.nutrivanceBrowserFocusAddressBar.rawValue),
        ]
        builder.replace(menu: .file, with: fileElements)

        let windowElements: [UIMenuElement] = [
            UIKeyCommand(title: "Show All Tabs", action: postSceneSelector, input: "\\", modifierFlags: cmdShift, propertyList: Notification.Name.nutrivanceBrowserShowAllTabs.rawValue),
        ]
        builder.replace(menu: .window, with: windowElements)
    }

    @MainActor
    private static func makeViewControlElements() -> [UIMenuElement] {
        guard let nav = NutrivanceMenuStateBinder.shared.activeNavigationState else {
            return [disabledPlaceholder()]
        }
        let tab = nav.selectedRootTab
        let items: [UIMenuElement]

        let left = UIKeyCommand.inputLeftArrow
        let right = UIKeyCommand.inputRightArrow

        switch tab {
        case .strainRecovery:
            items = [
                vcKey("Today", .nutrivanceViewControlToday, input: "t", cmdShift),
                vcKey("Previous", .nutrivanceViewControlPrevious, input: left, cmd),
                vcKey("Next", .nutrivanceViewControlNext, input: right, cmd),
                vcKey("1W", .nutrivanceViewControlFilter1, input: "1", cmd),
                vcKey("1M", .nutrivanceViewControlFilter2, input: "2", cmd),
                vcKey("1D", .nutrivanceViewControlFilter3, input: "3", cmd),
                vcKey("Refresh Coach Summary", .nutrivanceViewControlRefresh, input: "r", cmd),
                vcKey("Save Coach Summary to Journal", .nutrivanceViewControlSaveToJournal, input: "s", cmdOpt)
            ]
        case .stress:
            items = [
                vcKey("Today", .nutrivanceViewControlToday, input: "t", cmdOpt),
                vcKey("Previous", .nutrivanceViewControlPrevious, input: left, cmd),
                vcKey("Next", .nutrivanceViewControlNext, input: right, cmd),
                vcKey("24H", .nutrivanceViewControlFilter1, input: "1", cmd),
                vcKey("1W", .nutrivanceViewControlFilter2, input: "2", cmd),
                vcKey("1M", .nutrivanceViewControlFilter3, input: "3", cmd)
            ]
        case .sleep:
            items = [
                vcKey("Today", .nutrivanceViewControlToday, input: "t", cmdShift),
                vcKey("Previous", .nutrivanceViewControlPrevious, input: left, cmd),
                vcKey("Next", .nutrivanceViewControlNext, input: right, cmd),
                vcKey("Night", .nutrivanceViewControlFilter1, input: "1", cmd),
                vcKey("Week", .nutrivanceViewControlFilter2, input: "2", cmd),
                vcKey("Month", .nutrivanceViewControlFilter3, input: "3", cmd),
                vcKey("Year", .nutrivanceViewControlFilter4, input: "4", cmd),
                vcKey("Expand/Collapse Stages", .nutrivanceViewControlExpandCollapse, input: "e", cmd),
                vcKey("Wake Alarms", .nutrivanceViewControlSleepWakeAlarms, input: "u", cmd)
            ]
        case .pastQuests:
            items = [
                vcKey("Today", .nutrivanceViewControlToday, input: "t", cmdShift),
                vcKey("Previous", .nutrivanceViewControlPastQuestsPrevious, input: left, cmd),
                vcKey("Next", .nutrivanceViewControlPastQuestsNext, input: right, cmd),
                vcKey("7d", .nutrivanceViewControlFilter1, input: "1", cmd),
                vcKey("28d", .nutrivanceViewControlFilter2, input: "2", cmd),
                vcKey("Year", .nutrivanceViewControlFilter3, input: "3", cmd),
                vcKey("Log New Quest", .nutrivanceViewControlLogNewQuest, input: "n", cmdShift)
            ]
        case .journal:
            items = [
                vcKey("New Journal Entry", .nutrivanceViewControlNewJournalEntry, input: "n", cmdShift)
            ]
        case .pathfinder:
            items = [
                vcKey("Log Emotion", .nutrivanceViewControlPathfinderLogEmotion, input: "n", cmdShift)
            ]
        case .trainingCalendar:
            items = [
                vcKey("Today", .nutrivanceViewControlTrainingCalendarToday, input: "t", cmd),
                vcKey("Previous Day", .nutrivanceViewControlTrainingCalendarPreviousDay, input: left, cmd),
                vcKey("Next Day", .nutrivanceViewControlTrainingCalendarNextDay, input: right, cmd),
                vcKey("Previous Month", .nutrivanceViewControlTrainingCalendarPreviousMonth, input: left, cmdOpt),
                vcKey("Next Month", .nutrivanceViewControlTrainingCalendarNextMonth, input: right, cmdOpt),
                vcKey("Refresh Calendar", .nutrivanceViewControlTrainingCalendarRefresh, input: "r", cmd),
                vcKey("HR Zone Settings", .nutrivanceViewControlTrainingCalendarHRZoneSettings, input: "u", cmd)
            ]
        case .workoutHistory:
            items = [
                vcKey("Refresh Workouts", .nutrivanceViewControlRefreshWorkouts, input: "r", cmd),
                vcKey("HR Zone Settings", .nutrivanceViewControlHRZoneSettings, input: "u", cmd)
            ]
        case .recoveryScore:
            items = [
                vcKey("1D", .nutrivanceViewControlRecoveryScoreFilter1D, input: "1", cmd),
                vcKey("1W", .nutrivanceViewControlRecoveryScoreFilter1W, input: "2", cmd),
                vcKey("1M", .nutrivanceViewControlRecoveryScoreFilter1M, input: "3", cmd),
                vcKey("Refresh", .nutrivanceViewControlRecoveryScoreRefresh, input: "r", cmd)
            ]
        case .readiness:
            items = [
                vcKey("Refresh", .nutrivanceViewControlReadinessRefresh, input: "r", cmd)
            ]
        case .dashboard:
            items = [
                vcKey("7 Days", .nutrivanceViewControlChartRange7d, input: "1", cmd),
                vcKey("30 Days", .nutrivanceViewControlChartRange30d, input: "2", cmd),
                vcKey("Feel Good Score", .nutrivanceViewControlChartRangeFeelGood, input: "3", cmd),
                vcKey("Display Units", .nutrivanceViewControlDisplayUnits, input: "u", cmd),
                vcKey("Arrange Dashboard", .nutrivanceViewControlArrangeDashboard, input: "e", cmd)
            ]
        case .programBuilder:
            items = [
                vcKey("Workout Views", .nutrivanceViewControlWorkoutViews, input: "e", cmd),
                vcKey("Workout Metric Layout", .nutrivanceViewControlWorkoutMetricLayout, input: "u", cmd)
            ]
        case .heartZones:
            var hz: [UIMenuElement] = [
                vcKey("Today", .nutrivanceViewControlToday, input: "t", cmdShift),
                vcKey("Previous", .nutrivanceViewControlPrevious, input: left, cmd),
                vcKey("Next", .nutrivanceViewControlNext, input: right, cmd),
                vcKey("1D", .nutrivanceViewControlFilter1, input: "1", cmd),
                vcKey("1W", .nutrivanceViewControlFilter2, input: "2", cmd),
                vcKey("1M", .nutrivanceViewControlFilter3, input: "3", cmd)
            ]
            hz.append(hzKey("All Sports", slot: 0, input: "1", opt))
            hz.append(hzKey(heartZonesSportTitle(slot: 1), slot: 1, input: "2", opt))
            hz.append(hzKey(heartZonesSportTitle(slot: 2), slot: 2, input: "3", opt))
            hz.append(hzKey(heartZonesSportTitle(slot: 3), slot: 3, input: "4", opt))
            hz.append(hzKey(heartZonesSportTitle(slot: 4), slot: 4, input: "5", opt))
            hz.append(hzKey(heartZonesSportTitle(slot: 5), slot: 5, input: "6", opt))
            hz.append(hzKey(heartZonesSportTitle(slot: 6), slot: 6, input: "7", opt))
            hz.append(hzKey(heartZonesSportTitle(slot: 7), slot: 7, input: "8", opt))
            hz.append(hzKey(heartZonesSportTitle(slot: 8), slot: 8, input: "9", opt))
            hz.append(hzKey(heartZonesSportTitle(slot: 9), slot: 9, input: "0", opt))
            items = hz
        default:
            return [disabledPlaceholder()]
        }

        return items
    }

    private static func heartZonesSportTitle(slot: Int) -> String {
        switch slot {
        case 1: return "Sport: 2nd in List"
        case 2: return "Sport: 3rd in List"
        case 3: return "Sport: 4th in List"
        case 4: return "Sport: 5th in List"
        case 5: return "Sport: 6th in List"
        case 6: return "Sport: 7th in List"
        case 7: return "Sport: 8th in List"
        case 8: return "Sport: 9th in List"
        case 9: return "Sport: 10th in List"
        default: return "Sport"
        }
    }

    private static func disabledPlaceholder() -> UICommand {
        UICommand(
            title: "No View Controls Available",
            image: nil,
            action: noOpSelector,
            propertyList: nil,
            alternates: [],
            discoverabilityTitle: nil,
            attributes: [],
            state: .off
        )
    }
}
