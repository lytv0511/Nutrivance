import SwiftUI

// MARK: - Mac Catalyst “Optimize for Mac” idiom
// UIPickerView-backed wheel pickers are unavailable on Catalyst in the Mac idiom.
// Use menu-style pickers and compact date pickers instead. See UIBehavioralStyle in UIKit.

extension View {
    /// Wheel on iPhone/iPad; dropdown menu on Mac Catalyst (Mac idiom).
    @ViewBuilder
    func pickerStyleWheelOrMenuForCatalyst() -> some View {
        #if targetEnvironment(macCatalyst)
        self.pickerStyle(.menu)
        #else
        self.pickerStyle(.wheel)
        #endif
    }

    /// Wheel on iPhone/iPad; compact field on Mac Catalyst.
    @ViewBuilder
    func datePickerStyleWheelOrCompactForCatalyst() -> some View {
        #if targetEnvironment(macCatalyst)
        self.datePickerStyle(.compact)
        #else
        self.datePickerStyle(.wheel)
        #endif
    }

    /// Applies a fixed wheel height only on platforms where the wheel exists.
    @ViewBuilder
    func wheelPickerFixedHeight(_ height: CGFloat) -> some View {
        #if targetEnvironment(macCatalyst)
        self
        #else
        self.frame(height: height).clipped()
        #endif
    }
}
