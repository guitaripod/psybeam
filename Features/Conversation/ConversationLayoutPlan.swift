import UIKit

/// Where the conversation screen puts its two zones, decided from the window
/// size, the safe area and the fold, never from the device. The caption zone
/// holds the status, translation and source lines; the control zone holds the
/// two talk buttons. Both are horizontal extents in the screen's coordinates,
/// so nothing sits under a vertical bar or on the fold.
nonisolated struct ConversationLayoutPlan: Equatable, Sendable {
    enum Arrangement: Equatable, Sendable {
        case stacked
        case sideBySide
    }

    static let phoneCaptionPointSize: CGFloat = 36
    static let wideCaptionPointSize: CGFloat = 46
    static let defaultButtonHeight: CGFloat = 116

    private static let captionInset: CGFloat = 28
    private static let controlInset: CGFloat = 20
    private static let foldGap: CGFloat = 12
    private static let defaultCaptionOffset: CGFloat = -40
    private static let wideCaptionOffset: CGFloat = -8
    private static let buttonSpacing: CGFloat = 14
    private static let bottomClearance: CGFloat = 24
    private static let badgeClearance: CGFloat = 34
    private static let coachClearance: CGFloat = 60
    private static let stackedButtonHeights: ClosedRange<CGFloat> = 116...260
    private static let sideButtonHeights: ClosedRange<CGFloat> = 88...160
    private static let widePointSizeThreshold: CGFloat = 520
    private static let sideBySideCaptionShare: CGFloat = 0.55

    let arrangement: Arrangement
    let captionColumn: ClosedRange<CGFloat>
    let controlColumn: ClosedRange<CGFloat>
    let languageBarCenterX: CGFloat
    let captionCenterOffset: CGFloat
    let buttonRowHeight: CGFloat
    let captionPointSize: CGFloat

    /// `fold` is the division region in the screen's coordinates, inactive or
    /// not, and `topBarBottom` the lowest edge of the gear and language bar.
    init(size: CGSize, safeInsets: UIEdgeInsets, fold: CGRect?, topBarBottom: CGFloat) {
        let leading = safeInsets.left
        let trailing = size.width - safeInsets.right
        let bottom = size.height - safeInsets.bottom
        let verticalFold = fold.flatMap { $0.height >= $0.width ? $0 : nil }
        let horizontalFold = fold.flatMap { $0.width > $0.height ? $0 : nil }

        if size.width > size.height {
            arrangement = .sideBySide
            let caption: ClosedRange<CGFloat>
            let control: ClosedRange<CGFloat>
            if let verticalFold, verticalFold.midX > leading, verticalFold.midX < trailing {
                caption = Self.span(leading + Self.captionInset, verticalFold.minX - Self.foldGap)
                control = Self.span(verticalFold.maxX + Self.foldGap, trailing - Self.controlInset)
                languageBarCenterX = (control.lowerBound + control.upperBound) / 2
            } else {
                let split = leading + (trailing - leading) * Self.sideBySideCaptionShare
                caption = Self.span(leading + Self.captionInset, split - Self.foldGap)
                control = Self.span(split + Self.foldGap, trailing - Self.controlInset)
                languageBarCenterX = (leading + trailing) / 2
            }
            captionColumn = caption
            controlColumn = control
            captionCenterOffset = Self.wideCaptionOffset
            let room = bottom - Self.badgeClearance - Self.bottomClearance - topBarBottom
            let each = ((room - Self.buttonSpacing) / 2).clamped(to: Self.sideButtonHeights)
            buttonRowHeight = each * 2 + Self.buttonSpacing
        } else {
            arrangement = .stacked
            captionColumn = Self.span(leading + Self.captionInset, trailing - Self.captionInset)
            controlColumn = Self.span(leading + Self.controlInset, trailing - Self.controlInset)
            languageBarCenterX = (leading + trailing) / 2
            if let horizontalFold {
                let topCenter = (topBarBottom + horizontalFold.minY) / 2
                captionCenterOffset = topCenter - size.height / 2
                let room = bottom - horizontalFold.maxY - Self.bottomClearance - Self.badgeClearance - Self.coachClearance
                buttonRowHeight = room.clamped(to: Self.stackedButtonHeights)
            } else {
                captionCenterOffset = Self.defaultCaptionOffset
                buttonRowHeight = Self.defaultButtonHeight
            }
        }
        let width = captionColumn.upperBound - captionColumn.lowerBound
        captionPointSize = width >= Self.widePointSizeThreshold ? Self.wideCaptionPointSize : Self.phoneCaptionPointSize
    }

    /// A column, never negative in width, however narrow the window.
    private static func span(_ lower: CGFloat, _ upper: CGFloat) -> ClosedRange<CGFloat> {
        lower...max(lower, upper)
    }
}

extension Comparable {
    nonisolated fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
