import AppKit
import SwiftUI
import XCTest
@testable import LingoFloat

@MainActor
final class CCHUDWindowTests: XCTestCase {
    func testFirstPresentationRestoresPerDisplaySize() throws {
        let store = SettingsStore()
        let controller = CCHUDController(stream: CaptionStream(), store: store)
        controller.showDemo()
        let window = try XCTUnwrap(NSApp.windows.last { $0.identifier == CCHUDController.windowIdentifier })
        defer { window.close() }
        let screen = try XCTUnwrap(store.targetDisplayUUID.flatMap { Displays.screen(forUUID: $0) } ?? NSScreen.main)
        XCTAssertEqual(window.frame.width,
                       screen.frame.width * store.ccHUDWidthFraction(forDisplayUUID: screen.wc_displayUUID), accuracy: 1)
        XCTAssertEqual(window.frame.height,
                       store.ccHUDHeight(forDisplayUUID: screen.wc_displayUUID), accuracy: 1)
        withExtendedLifetime(controller) {}
    }

    func testHitTestingUsesSuperviewCoordinates() {
        let parent = FlippedView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        let interaction = HUDWindowInteractionView(frame: NSRect(x: 70, y: 100, width: 600, height: 240))
        parent.addSubview(interaction)
        for point in [NSPoint(x: 300, y: 2), NSPoint(x: 300, y: 238),
                      NSPoint(x: 2, y: 120), NSPoint(x: 598, y: 120)] {
            XCTAssertTrue(interaction.hitTest(parent.convert(point, from: interaction)) === interaction)
        }
        XCTAssertNil(interaction.hitTest(parent.convert(NSPoint(x: 300, y: 120), from: interaction)))
        XCTAssertNil(interaction.hitTest(parent.convert(NSPoint(x: -5, y: 120), from: interaction)))
        XCTAssertNil(interaction.hitTest(parent.convert(NSPoint(x: 550, y: 230), from: interaction)),
                     "Clear button area must pass clicks through to SwiftUI")
    }

    func testRoundedPlateHasTransparentCorners() throws {
        let renderer = ImageRenderer(content: CCHUDView(captions: [], backgroundOpacity: 0.7)
            .frame(width: 600, height: 160))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)
        for (x, y) in [(0, 0), (1199, 0), (0, 319), (1199, 319),
                       (4, 4), (1195, 4), (4, 315), (1195, 315)] {
            XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent, 0.01,
                              "Nontransparent pixel at \(x), \(y)")
        }
        let plate = try XCTUnwrap(bitmap.colorAt(x: 600, y: 60))
        XCTAssertGreaterThan(plate.alphaComponent, 0.65, "Ensure we rendered the real plate, not a blank image")
        XCTAssertLessThan(plate.alphaComponent, 0.75)
    }

    func testWindowAndInteractionRespectShortHeight() async throws {
        let savedFrameKey = "NSWindow Frame LingoFloat.CCHUD.v2"
        let savedFrame = UserDefaults.standard.object(forKey: savedFrameKey)
        defer { UserDefaults.standard.set(savedFrame, forKey: savedFrameKey) }
        let controller = CCHUDController(stream: CaptionStream(), store: SettingsStore())
        controller.showDemo()
        let window = try XCTUnwrap(NSApp.windows.last { $0.identifier == CCHUDController.windowIdentifier })
        defer { window.close() }
        for height in [320.0, 160, 90, 64, 240, 80] {
            let requested = NSRect(x: 400, y: 200, width: 700, height: height)
            window.setFrame(requested, display: true)
            window.contentView?.layoutSubtreeIfNeeded()
            await Task.yield()
            window.contentView?.layoutSubtreeIfNeeded()
            XCTAssertEqual(window.frame, requested)
            let interaction = try XCTUnwrap(findInteraction(in: try XCTUnwrap(window.contentView)))
            XCTAssertEqual(interaction.bounds.height, height, accuracy: 1,
                           "Hit area must follow the window, not the subtitle's natural height")
        }
        withExtendedLifetime(controller) {}
    }

    func testPersistingDragAndChangingAppearanceDoNotRepositionWindow() async throws {
        let keys = ["NSWindow Frame LingoFloat.CCHUD.v2", "LingoFloat.settings.ccHUDWidthFractionByDisplay",
                    "LingoFloat.settings.ccHUDHeightByDisplay", "LingoFloat.settings.ccHUDCenterXFractionByDisplay",
                    "LingoFloat.settings.ccHUDBottomOffsetByDisplay", "LingoFloat.settings.ccBackgroundColorHex"]
        let defaults = UserDefaults.standard
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
        let store = SettingsStore()
        let controller = CCHUDController(stream: CaptionStream(), store: store)
        controller.showDemo()
        let window = try XCTUnwrap(NSApp.windows.last { $0.identifier == CCHUDController.windowIdentifier } as? CCHUDPanel)
        defer { window.close() }
        // Exercise both monitors on a multi-display workstation, including negative origins.
        for screen in NSScreen.screens {
            let expected = NSRect(x: screen.frame.minX + 80, y: screen.frame.minY + 150,
                                  width: screen.frame.width * 0.4, height: 180)
            window.setFrame(expected, display: true)
            window.finishUserGeometryChange()
            await Task.yield()
            XCTAssertEqual(window.frame, expected)
            store.ccBackgroundColorHex = store.ccBackgroundColorHex == "#010101" ? "#020202" : "#010101"
            await Task.yield()
            XCTAssertEqual(window.frame, expected)
            let uuid = try XCTUnwrap(screen.wc_displayUUID)
            XCTAssertEqual(store.ccHUDHeight(forDisplayUUID: uuid), 180, accuracy: 0.5)
        }
        withExtendedLifetime(controller) {}
    }

    func testNativeContentHasTransparentCorners() async throws {
        let (window, content) = makePanel()
        defer { window.close() }
        window.orderFrontRegardless()
        await Task.yield()
        content.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: bitmap)
        let attachment = XCTAttachment(data: try XCTUnwrap(bitmap.representation(using: .png, properties: [:])),
                                       uniformTypeIdentifier: "public.png")
        attachment.name = "HUD native transparent corners"
        attachment.lifetime = .keepAlways
        add(attachment)
        for (x, y) in [(1, 1), (bitmap.pixelsWide - 2, 1),
                       (1, bitmap.pixelsHigh - 2), (bitmap.pixelsWide - 2, bitmap.pixelsHigh - 2)] {
            XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent, 0.01)
        }
        let center = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 4))
        XCTAssertGreaterThan(center.alphaComponent, 0.65)
        XCTAssertLessThan(center.alphaComponent, 0.75)
    }

    func testAllEdgesAndCornersKeepOppositeEdgeAnchoredWithoutCreep() throws {
        let (window, content) = makePanel()
        defer { window.close() }
        let interaction = try XCTUnwrap(findInteraction(in: content))
        let initial = window.frame
        var completed = 0
        window.onUserGeometryChangeEnded = { _ in completed += 1 }
        // Inner half of each corner must use the same diagonal resize as its cursor.
        for (x, y, left, right, bottom, top) in [
            (12.0, 12.0, true, false, true, false),
            (688, 12, false, true, true, false),
            (12, 228, true, false, false, true),
            (688, 228, false, true, false, true),
            (2, 120, true, false, false, false),
            (698, 120, false, true, false, false),
            (350, 2, false, false, true, false),
            (350, 238, false, false, false, true)
        ] {
            window.setFrame(initial, display: true)
            let start = NSPoint(x: initial.minX + x, y: initial.minY + y)
            interaction.mouseDown(with: event(.leftMouseDown, screenPoint: start, window: window))
            for step in [1.0, 2, 3, 3, 3, 2, 1, 0] {
                let dx = step * 10, dy = step * 10
                let point = NSPoint(x: start.x + dx, y: start.y + dy)
                interaction.mouseDragged(with: event(.leftMouseDragged, screenPoint: point, window: window))
                content.layoutSubtreeIfNeeded()
                XCTAssertEqual(window.frame.width, initial.width + (left ? -dx : right ? dx : 0), accuracy: 0.5)
                XCTAssertEqual(window.frame.height, initial.height + (bottom ? -dy : top ? dy : 0), accuracy: 0.5)
                XCTAssertEqual(window.frame.minX, initial.minX + (left ? dx : 0), accuracy: 0.5)
                XCTAssertEqual(window.frame.minY, initial.minY + (bottom ? dy : 0), accuracy: 0.5)
            }
            interaction.mouseUp(with: event(.leftMouseUp, screenPoint: start, window: window))
        }
        XCTAssertEqual(completed, 8)
    }

    func testVerticalLimitsAndCaptionRefreshDuringDrag() async throws {
        let (window, content) = makePanel()
        defer { window.close() }
        let interaction = try XCTUnwrap(findInteraction(in: content))
        let initial = window.frame
        let start = NSPoint(x: initial.midX, y: initial.maxY - 2)
        interaction.mouseDown(with: event(.leftMouseDown, screenPoint: start, window: window))
        for (delta, expected) in [(2000.0, 600.0), (-2000, 64), (40, 280), (40, 280), (0, 240)] {
            content.host.rootView = CCHUDView(captions: [Caption(source: .system,
                text: String(repeating: "字幕保持正常字号。Long captions must not resize the window. ", count: 25),
                language: .en, isFinal: false)], backgroundOpacity: 0.7)
            let point = NSPoint(x: start.x, y: start.y + delta)
            interaction.mouseDragged(with: event(.leftMouseDragged, screenPoint: point, window: window))
            await Task.yield()
            content.layoutSubtreeIfNeeded()
            XCTAssertEqual(window.frame.height, expected, accuracy: 0.5)
            XCTAssertEqual(window.frame.width, initial.width, accuracy: 0.5)
            XCTAssertEqual(window.frame.minY, initial.minY, accuracy: 0.5)
            XCTAssertEqual(interaction.bounds.height, expected, accuracy: 0.5)
        }
        interaction.mouseUp(with: event(.leftMouseUp, screenPoint: start, window: window))
    }

    private func makePanel() -> (CCHUDPanel, CCHUDContentView) {
        let screen = NSScreen.screens[0].frame
        let window = CCHUDPanel(contentRect: NSRect(x: screen.minX + 300, y: screen.minY + 100,
                                                   width: 700, height: 240),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 280, height: 64)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        let content = CCHUDContentView(rootView: CCHUDView(captions: [], backgroundOpacity: 0.7))
        window.contentView = content
        content.layoutSubtreeIfNeeded()
        return (window, content)
    }

    private func event(_ type: NSEvent.EventType, screenPoint: NSPoint, window: NSWindow) -> NSEvent {
        // Replace only the OS pointer input; the native event handlers, frame
        // changes, hosting layout and geometry persistence remain real.
        findInteraction(in: window.contentView!)?.screenMouseLocation = { screenPoint }
        return NSEvent.mouseEvent(with: type, location: window.convertPoint(fromScreen: screenPoint),
                          modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                          context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    func testQueuedLocalCoordinatesCannotAmplifyVerticalResize() throws {
        let (window, content) = makePanel()
        defer { window.close() }
        let interaction = try XCTUnwrap(findInteraction(in: content))
        let initial = window.frame
        let start = NSPoint(x: initial.midX, y: initial.minY + 2)
        interaction.mouseDown(with: event(.leftMouseDown, screenPoint: start, window: window))
        let end = NSPoint(x: start.x, y: start.y - 40)
        let queued = event(.leftMouseDragged, screenPoint: end, window: window)
        for _ in 0..<20 {
            // Re-deliver the same local coordinates after the bottom edge has
            // moved. A stationary screen pointer must NOT keep growing the HUD.
            interaction.mouseDragged(with: queued)
            XCTAssertEqual(window.frame.height, initial.height + 40, accuracy: 0.5)
            XCTAssertEqual(window.frame.maxY, initial.maxY, accuracy: 0.5)
        }
        interaction.mouseUp(with: event(.leftMouseUp, screenPoint: end, window: window))
    }

    private func findInteraction(in view: NSView) -> HUDWindowInteractionView? {
        if let interaction = view as? HUDWindowInteractionView { return interaction }
        return view.subviews.lazy.compactMap { self.findInteraction(in: $0) }.first
    }

    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }
}
