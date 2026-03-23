import SwiftUI

enum ChartInteractionSmoothing {
    static let horizontalTolerance: CGFloat = 20
    static let verticalTolerance: CGFloat = 14
    static let horizontalInset: CGFloat = 1

    static func clampedXPosition(
        for location: CGPoint,
        plotFrame: CGRect
    ) -> CGFloat? {
        let expandedFrame = plotFrame.insetBy(dx: -horizontalTolerance, dy: -verticalTolerance)
        guard expandedFrame.contains(location) else { return nil }

        let safeMinX = plotFrame.minX + horizontalInset
        let safeMaxX = max(safeMinX, plotFrame.maxX - horizontalInset)
        let clampedX = min(max(location.x, safeMinX), safeMaxX)
        return clampedX - plotFrame.minX
    }

    static func fallbackBoundaryDate<T>(
        for xPosition: CGFloat,
        plotFrame: CGRect,
        data: [(Date, T)]
    ) -> Date? {
        guard let firstDate = data.first?.0, let lastDate = data.last?.0 else {
            return nil
        }

        return xPosition <= plotFrame.width / 2 ? firstDate : lastDate
    }
}
