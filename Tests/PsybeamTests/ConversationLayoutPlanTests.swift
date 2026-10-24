import Testing
import UIKit
@testable import Psybeam

@Suite("Conversation layout plan")
struct ConversationLayoutPlanTests {
    private let topBar: CGFloat = 148

    @Test("A phone-sized portrait window keeps the stacked layout and its default metrics")
    func phonePortrait() {
        let plan = ConversationLayoutPlan(
            size: CGSize(width: 393, height: 852), safeInsets: .zero, fold: nil, topBarBottom: topBar)
        #expect(plan.arrangement == .stacked)
        #expect(plan.captionColumn == 28...365)
        #expect(plan.controlColumn == 20...373)
        #expect(plan.captionCenterOffset == -40)
        #expect(plan.buttonRowHeight == ConversationLayoutPlan.defaultButtonHeight)
        #expect(plan.captionPointSize == ConversationLayoutPlan.phoneCaptionPointSize)
    }

    @Test("A vertical bar's inset moves both columns and the language bar off it")
    func verticalBarInset() {
        let plan = ConversationLayoutPlan(
            size: CGSize(width: 466, height: 678),
            safeInsets: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 84), fold: nil, topBarBottom: 66)
        #expect(plan.captionColumn.upperBound == 354)
        #expect(plan.controlColumn.upperBound == 362)
        #expect(plan.languageBarCenterX == 191)
    }

    @Test("A horizontal fold puts the caption above it and enlarges the buttons below it")
    func horizontalFold() {
        let fold = CGRect(x: 0, y: 455.5, width: 669, height: 40)
        let plan = ConversationLayoutPlan(
            size: CGSize(width: 669, height: 951),
            safeInsets: UIEdgeInsets(top: 82, left: 0, bottom: 34, right: 0), fold: fold, topBarBottom: 148)
        let captionCenter = 951 / 2 + plan.captionCenterOffset
        #expect(captionCenter > 148)
        #expect(captionCenter < fold.minY)
        #expect(plan.buttonRowHeight > ConversationLayoutPlan.defaultButtonHeight)
        #expect(plan.captionPointSize == ConversationLayoutPlan.wideCaptionPointSize)
    }

    @Test("A vertical fold separates the caption zone from the control zone")
    func verticalFold() {
        let fold = CGRect(x: 455.5, y: 0, width: 40, height: 669)
        let plan = ConversationLayoutPlan(
            size: CGSize(width: 951, height: 669),
            safeInsets: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 84), fold: fold, topBarBottom: 66)
        #expect(plan.arrangement == .sideBySide)
        #expect(plan.captionColumn.upperBound < fold.minX)
        #expect(plan.controlColumn.lowerBound > fold.maxX)
        #expect(plan.controlColumn.upperBound <= 867)
        #expect(plan.languageBarCenterX > fold.maxX)
    }

    @Test("A wide window with no fold splits by share and centres the language bar")
    func wideWithoutFold() {
        let plan = ConversationLayoutPlan(
            size: CGSize(width: 678, height: 466),
            safeInsets: UIEdgeInsets(top: 0, left: 84, bottom: 21, right: 0), fold: nil, topBarBottom: 66)
        #expect(plan.arrangement == .sideBySide)
        #expect(plan.captionColumn.lowerBound == 112)
        #expect(plan.captionColumn.upperBound < plan.controlColumn.lowerBound)
        #expect(plan.languageBarCenterX == 381)
        #expect(plan.buttonRowHeight >= 88 * 2 + 14)
    }

    @Test("A degenerate window never yields a negative column")
    func narrowestWindow() {
        let plan = ConversationLayoutPlan(
            size: CGSize(width: 60, height: 40), safeInsets: UIEdgeInsets(top: 0, left: 30, bottom: 0, right: 30),
            fold: nil, topBarBottom: 66)
        #expect(plan.captionColumn.lowerBound <= plan.captionColumn.upperBound)
        #expect(plan.controlColumn.lowerBound <= plan.controlColumn.upperBound)
    }
}
