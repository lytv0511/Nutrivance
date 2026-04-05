import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - QA checklist (Mac Catalyst, repeat after substantive UI changes)
//
// 1. System Settings → Keyboard → enable Full Keyboard Access (optional but recommended).
// 2. Tab forward through visible controls; Shift-Tab backward — no infinite skip loops on a screen.
// 3. Space and Return activate the focused control (toggle / button) where applicable.
// 4. Compare with pointer: focused control matches expected target.
// 5. iPhone / iPad touch: no regression (modifiers are no-ops off Catalyst).

/// Keyboard focus helpers for **Mac Catalyst**. Keeps iOS/iPad touch behavior unchanged.
enum CatalystKeyboardNavigation {
    static var isDesktopKeyboardChrome: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }
}

// MARK: - Split view / sidebar focus ring

/// System keyboard focus rectangles can draw in the wrong coordinate space when detail content lives beside a
/// `TabView` sidebar (e.g. `.sidebarAdaptable` on Mac Catalyst). A locally laid-out ring tracks the view correctly.
private struct SplitViewSafeKeyboardFocusRing: ViewModifier {
    @Environment(\.isFocused) private var isFocused
    var cornerRadius: CGFloat

    /// UIKit does not expose `keyboardFocusIndicatorColor` like AppKit; match the usual system focus blue in light/dark.
    private var ringColor: Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 64 / 255, green: 156 / 255, blue: 1, alpha: 1)
                : UIColor(red: 0, green: 122 / 255, blue: 1, alpha: 1)
        })
        #else
        Color.accentColor
        #endif
    }

    func body(content: Content) -> some View {
        content.overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(ringColor, lineWidth: 2.5)
                    .padding(-3)
                    .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    /// Tab-focusable with a **local** focus ring **on Mac Catalyst only** when the system ring is drawn in the wrong place beside a `sidebarAdaptable` column.
    /// iPad uses plain `.focusable(true)` — pairing `focusEffectDisabled` + a custom ring with every control was breaking Tab / activation across the app.
    @ViewBuilder
    func splitViewSafeKeyboardFocusable(cornerRadius: CGFloat = 10) -> some View {
        #if targetEnvironment(macCatalyst)
        self
            .focusable(true)
            .focusEffectDisabled(true)
            .modifier(SplitViewSafeKeyboardFocusRing(cornerRadius: cornerRadius))
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

    /// Participates in the Tab key loop on Catalyst (custom `Button(.plain)` and similar often need this).
    @ViewBuilder
    func catalystDesktopFocusable() -> some View {
        #if targetEnvironment(macCatalyst)
        self.focusable(true)
        #else
        self
        #endif
    }

    /// For non-`Button` visuals that should toggle on Space / Return when focused (Catalyst only).
    @ViewBuilder
    func catalystInteractiveFocus(onActivate: @escaping () -> Void) -> some View {
        #if targetEnvironment(macCatalyst)
        self
            .focusable(true)
            .onKeyPress(.space, phases: .down) { _ in
                onActivate()
                return .handled
            }
            .onKeyPress(.return, phases: .down) { _ in
                onActivate()
                return .handled
            }
        #else
        self
        #endif
    }
}

/// `Toggle` with Catalyst tab focus. Use for settings rows where the stock toggle is hard to reach via keyboard.
struct CatalystAccessibleToggle: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool

    /// Unlabeled title matches `Toggle("…", isOn:)` call style (memberwise init would require `title:`).
    init(_ title: LocalizedStringKey, isOn: Binding<Bool>) {
        self.title = title
        self._isOn = isOn
    }

    var body: some View {
        Toggle(title, isOn: $isOn)
            .catalystDesktopFocusable()
    }
}
