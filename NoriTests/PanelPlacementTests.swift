import AppKit
import Foundation
import Testing
@testable import Nori

/// Panel geometry (§2): fixed width, clamped height, always fully on one screen.
@Suite("PanelPlacement")
@MainActor
struct PanelPlacementTests {
    private let visible = NSRect(x: 0, y: 25, width: 1440, height: 875)  // 1440×900 minus a 25 pt Dock strip
    private let size = NSSize(width: PanelPlacement.width, height: 620)

    @Test func fixedWidthAndHeightBounds() {
        #expect(PanelPlacement.width == 560)
        #expect(PanelPlacement.minHeight == 320)
        #expect(PanelPlacement.maxHeight == 620)
    }

    @Test func heightIsThreeQuartersOfTheScreenClamped() {
        #expect(PanelPlacement.height(for: nil) == 620, "no screen: 900 × 0.75 = 675, clamped to 620")
        #expect(PanelPlacement.height(forVisibleHeight: 900) == 620)
        #expect(PanelPlacement.height(forVisibleHeight: 800) == 600, "floor(800 × 0.75)")
        #expect(PanelPlacement.height(forVisibleHeight: 801) == 600, "floor, not round")
        #expect(PanelPlacement.height(forVisibleHeight: 400) == 320, "never below the minimum")
        #expect(PanelPlacement.height(forVisibleHeight: 0) == 320)
        #expect(PanelPlacement.height(forVisibleHeight: 5_000) == 620, "never above the maximum")
        #expect(PanelPlacement.height(forVisibleHeight: 826.66) == 619)
    }

    @Test func constrainLeavesAFittingOriginAlone() {
        let origin = NSPoint(x: 300, y: 100)
        #expect(PanelPlacement.constrain(origin, size: size, in: visible) == origin)
        #expect(PanelPlacement.constrain(origin, size: size, to: nil) == origin, "no screen: nothing to clamp against")
    }

    @Test func constrainPullsEveryEdgeInside() {
        // Off the right and top (a pointer near the top-right corner).
        let topRight = PanelPlacement.constrain(NSPoint(x: 1400, y: 890), size: size, in: visible)
        #expect(topRight == NSPoint(x: 1440 - 560, y: 900 - 620))
        #expect(NSRect(origin: topRight, size: size).maxX == visible.maxX)
        #expect(NSRect(origin: topRight, size: size).maxY == visible.maxY)

        // Off the left and below the Dock.
        let bottomLeft = PanelPlacement.constrain(NSPoint(x: -50, y: -400), size: size, in: visible)
        #expect(bottomLeft == NSPoint(x: 0, y: 25))
        #expect(visible.contains(NSRect(origin: bottomLeft, size: size)))

        // Exactly on the edge stays put.
        let edge = NSPoint(x: visible.maxX - size.width, y: visible.maxY - size.height)
        #expect(PanelPlacement.constrain(edge, size: size, in: visible) == edge)
    }

    @Test func constrainedFrameIsAlwaysInsideTheVisibleFrame() {
        let candidates: [NSPoint] = [
            .zero, NSPoint(x: -1_000, y: -1_000), NSPoint(x: 10_000, y: 10_000), NSPoint(x: 700, y: 450),
            NSPoint(x: 1_439, y: 26), NSPoint(x: 1, y: 899),
        ]
        for origin in candidates {
            let frame = NSRect(origin: PanelPlacement.constrain(origin, size: size, in: visible), size: size)
            #expect(visible.contains(frame), "origin \(origin) → \(frame)")
        }
    }

    @Test func aPanelLargerThanTheScreenPinsToTheBottomLeft() {
        let tiny = NSRect(x: 100, y: 100, width: 400, height: 300)
        let origin = PanelPlacement.constrain(NSPoint(x: 900, y: 900), size: size, in: tiny)
        #expect(origin == NSPoint(x: 100, y: 100), "the top-left of the panel stays visible")
    }

    @Test func secondaryScreenOffsetsAreRespected() {
        let secondary = NSRect(x: -1_920, y: 200, width: 1_920, height: 1_055)
        let origin = PanelPlacement.constrain(NSPoint(x: -10, y: 1_300), size: size, in: secondary)
        #expect(origin == NSPoint(x: -560, y: 1_255 - 620))
        #expect(secondary.contains(NSRect(origin: origin, size: size)))
    }
}
