import AppKit
import SwiftUI

/// SwiftUI body of the closed-caption HUD — a movie-style caption strip
/// docked to the bottom of the active display. Shows the LAST two
/// system-side captions:
///
///   Row 1  ← previous caption, dimmed
///   Row 2  ← current caption (may still be interim), bright
///
/// Background plate is solid black with user-tunable opacity. A soft
/// inner outline keeps the strip looking like a finished UI element
/// rather than a black rectangle painted on the desktop.
///
/// The view is owned by `CCHUDController`, which decides what to show
/// and when. The view itself is a dumb reader of two arrays + opacity.
struct CCHUDView: View {

    /// Captions to render. The controller passes 0–2 entries:
    ///   - 0  → controller will hide the panel before the view ever
    ///          renders (we still bail to nothing as a safety net).
    ///   - 1  → render as the "current" row, no previous row.
    ///   - 2  → previous (older) at index 0, current at index 1.
    let captions: [Caption]

    /// 0.0 ... 1.0 — applied to the background fill so the user
    /// can dial how much of the page bleeds through. Multiplied with the
    /// background colour's own alpha.
    let backgroundOpacity: Double

    /// User-configurable colours. Defaulted so the SwiftUI previews and
    /// any callers that haven't been updated still compile / render.
    let backgroundColor: Color
    let previousLineColor: Color
    let currentLineColor: Color
    let translationColor: Color
    let onClear: () -> Void

    init(
        captions: [Caption],
        backgroundOpacity: Double,
        backgroundColor: Color = .black,
        previousLineColor: Color = .white,
        currentLineColor: Color = .white,
        translationColor: Color = Color(red: 1.00, green: 0.85, blue: 0.40),
        onClear: @escaping () -> Void = {}
    ) {
        self.captions = captions
        self.backgroundOpacity = backgroundOpacity
        self.backgroundColor = backgroundColor
        self.previousLineColor = previousLineColor
        self.currentLineColor = currentLineColor
        self.translationColor = translationColor
        self.onClear = onClear
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .center) {
                background

                content
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                Capsule()
                    .fill(Color.white.opacity(0.28))
                    .frame(width: 42, height: 4)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 7)
                    .allowsHitTesting(false)

                if !captions.isEmpty {
                    Button("Clear", action: onClear)
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.20), in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.top, 5)
                        .padding(.trailing, 10)
                        .accessibilityIdentifier("cc-hud-clear-button")
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            // User-tinted plate with user-controlled opacity — sells the
            // "movie subtitles" feel and stays legible on any page.
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(backgroundColor.opacity(backgroundOpacity))

            // Hair-thin inner highlight (top edge). Keeps the strip from
            // reading as a flat black slab.
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.10), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.7
                )
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if captions.isEmpty {
            // User toggled the CC HUD on a chat with no system-side
            // captions yet. Show a tiny "waveform-at-rest" placeholder so
            // the panel feels alive.
            VStack(spacing: 4) {
                Text("░░░ ▁▁ ▂▂ ▃▃ ▂▂ ▁▁ ░░░")
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .tracking(2)
                Text("waiting for system audio…")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity, alignment: .center)
        } else {
            captionsBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .clipped()
        }
    }

    /// Keep the current subtitle at a stable movie-caption size. The prior
    /// context row is deliberately smaller and lower priority, so a short
    /// panel sacrifices old context before shrinking the words being spoken.
    private var captionsBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            if captions.count >= 2 {
                captionLine(captions[0], style: .previous)
            }
            captionLine(captions.last!, style: .current)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One caption rendered at the fixed size for its role.
    @ViewBuilder
    private func captionLine(_ caption: Caption, style: LineStyle) -> some View {
        let isCurrent = style == .current
        let lineColor = isCurrent ? currentLineColor : previousLineColor
        VStack(alignment: .leading, spacing: 2) {
            Text(caption.text)
                .font(.system(size: style.fontSize, weight: style.weight, design: .rounded))
                .foregroundStyle(lineColor)
                .opacity(isCurrent ? 1.0 : 0.55)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let translation = caption.translation, !translation.isEmpty {
                Text(translation)
                    .font(.system(size: style.translationSize, weight: .regular, design: .rounded))
                    .foregroundStyle(translationColor)
                    .opacity(isCurrent ? 0.95 : 0.55)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .layoutPriority(isCurrent ? 1 : 0)
    }

    private enum LineStyle {
        case previous, current

        var fontSize: CGFloat {
            switch self {
            case .previous: return 15
            case .current:  return 22
            }
        }

        var translationSize: CGFloat {
            switch self {
            case .previous: return 13
            case .current:  return 20
            }
        }

        /// Current row gets a heavier face so the user's eye lands there
        /// first regardless of the chosen size step.
        var weight: Font.Weight {
            switch self {
            case .previous: return .regular
            case .current:  return .semibold
            }
        }
    }
}

/// AppKit owns the frame and hit area; subtitle layout must never resize the panel.
final class CCHUDContentView: NSView {
    let host: NSHostingView<CCHUDView>

    override var isOpaque: Bool { false }

    init(rootView: CCHUDView) {
        host = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = 18
        layer?.masksToBounds = true
        host.sizingOptions = []
        host.safeAreaRegions = []
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        for view in [host, HUDWindowInteractionView()] {
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private struct HUDResizeEdges: OptionSet {
    let rawValue: UInt8

    static let left = HUDResizeEdges(rawValue: 1 << 0)
    static let right = HUDResizeEdges(rawValue: 1 << 1)
    static let top = HUDResizeEdges(rawValue: 1 << 2)
    static let bottom = HUDResizeEdges(rawValue: 1 << 3)
}

final class HUDWindowInteractionView: NSView {
    private static let resizeInset: CGFloat = 9
    private static let dragHeight: CGFloat = 24
    private static let clearButtonWidth: CGFloat = 76
    private static let clearButtonHeight: CGFloat = 34

    private var initialMouseLocation: NSPoint?
    private var initialWindowFrame: NSRect?
    private var initialScreenFrame: NSRect?
    private var activeResizeEdges: HUDResizeEdges = []
    private var isMovingWindow = false
    // A queued event may carry coordinates from before setFrame moved the
    // window. Read the screen pointer independently of the changing frame.
    var screenMouseLocation: () -> NSPoint = { NSEvent.mouseLocation }

    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let point = convert(point, from: superview)
        guard bounds.contains(point) else { return nil }
        let edges = resizeEdges(at: point)
        let clearButtonArea = NSRect(
            x: bounds.maxX - Self.clearButtonWidth - Self.resizeInset,
            y: bounds.maxY - Self.clearButtonHeight,
            width: Self.clearButtonWidth,
            height: Self.clearButtonHeight
        )
        if edges.isEmpty, clearButtonArea.contains(point) { return nil }
        let isInDragStrip = point.y >= bounds.maxY - Self.dragHeight
        return !edges.isEmpty || isInDragStrip ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let point = convert(event.locationInWindow, from: nil)
        activeResizeEdges = resizeEdges(at: point)
        isMovingWindow = activeResizeEdges.isEmpty
        initialMouseLocation = screenMouseLocation()
        initialWindowFrame = window.frame
        initialScreenFrame = (window.screen ?? NSScreen.main)?.frame ?? window.frame
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let initialMouseLocation, let initialWindowFrame, let initialScreenFrame else { return }

        let current = screenMouseLocation()
        let deltaX = current.x - initialMouseLocation.x
        let deltaY = current.y - initialMouseLocation.y
        var frame = initialWindowFrame

        if isMovingWindow {
            frame.origin.x += deltaX
            frame.origin.y += deltaY
            window.setFrameOrigin(frame.origin)
            return
        }

        let screenFrame = initialScreenFrame
        let minimumWidth = max(
            window.minSize.width,
            screenFrame.width * CGFloat(SettingsStore.ccHUDWidthFractionRange.lowerBound)
        )
        let maximumWidth = screenFrame.width * CGFloat(SettingsStore.ccHUDWidthFractionRange.upperBound)
        let minimumHeight = window.minSize.height
        let maximumHeight = min(screenFrame.height, CGFloat(SettingsStore.ccHUDHeightRange.upperBound))

        if activeResizeEdges.contains(.left) {
            let availableWidth = min(maximumWidth, initialWindowFrame.maxX - screenFrame.minX)
            frame.size.width = clamped(
                initialWindowFrame.width - deltaX,
                lower: minimumWidth,
                upper: availableWidth
            )
            frame.origin.x = initialWindowFrame.maxX - frame.width
        } else if activeResizeEdges.contains(.right) {
            let availableWidth = min(maximumWidth, screenFrame.maxX - initialWindowFrame.minX)
            frame.size.width = clamped(
                initialWindowFrame.width + deltaX,
                lower: minimumWidth,
                upper: availableWidth
            )
        }

        if activeResizeEdges.contains(.bottom) {
            let availableHeight = min(maximumHeight, initialWindowFrame.maxY - screenFrame.minY)
            frame.size.height = clamped(
                initialWindowFrame.height - deltaY,
                lower: minimumHeight,
                upper: availableHeight
            )
            frame.origin.y = initialWindowFrame.maxY - frame.height
        } else if activeResizeEdges.contains(.top) {
            let availableHeight = min(maximumHeight, screenFrame.maxY - initialWindowFrame.minY)
            frame.size.height = clamped(
                initialWindowFrame.height + deltaY,
                lower: minimumHeight,
                upper: availableHeight
            )
        }

        window.setFrame(frame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        (window as? CCHUDPanel)?.finishUserGeometryChange()
        initialMouseLocation = nil
        initialWindowFrame = nil
        initialScreenFrame = nil
        activeResizeEdges = []
        isMovingWindow = false
    }

    override func resetCursorRects() {
        let inset = Self.resizeInset
        let corner = inset * 2
        let horizontalLength = max(0, bounds.width - corner * 2)
        let verticalLength = max(0, bounds.height - corner * 2)

        addCursorRect(NSRect(x: 0, y: bounds.maxY - corner, width: corner, height: corner), cursor: resizeCursor(for: [.top, .left]))
        addCursorRect(NSRect(x: bounds.maxX - corner, y: bounds.maxY - corner, width: corner, height: corner), cursor: resizeCursor(for: [.top, .right]))
        addCursorRect(NSRect(x: 0, y: 0, width: corner, height: corner), cursor: resizeCursor(for: [.bottom, .left]))
        addCursorRect(NSRect(x: bounds.maxX - corner, y: 0, width: corner, height: corner), cursor: resizeCursor(for: [.bottom, .right]))

        addCursorRect(NSRect(x: corner, y: bounds.maxY - inset, width: horizontalLength, height: inset), cursor: resizeCursor(for: .top))
        addCursorRect(NSRect(x: corner, y: 0, width: horizontalLength, height: inset), cursor: resizeCursor(for: .bottom))
        addCursorRect(NSRect(x: 0, y: corner, width: inset, height: verticalLength), cursor: resizeCursor(for: .left))
        addCursorRect(NSRect(x: bounds.maxX - inset, y: corner, width: inset, height: verticalLength), cursor: resizeCursor(for: .right))

        addCursorRect(
            NSRect(
                x: corner,
                y: bounds.maxY - Self.dragHeight,
                width: max(0, horizontalLength - Self.clearButtonWidth),
                height: Self.dragHeight - inset
            ),
            cursor: .openHand
        )
    }

    private func resizeEdges(at point: NSPoint) -> HUDResizeEdges {
        // Match the 18pt corner cursor regions, including their inner halves.
        let corner = Self.resizeInset * 2
        if point.x < corner && point.y < corner { return [.bottom, .left] }
        if point.x > bounds.maxX - corner && point.y < corner { return [.bottom, .right] }
        if point.x < corner && point.y > bounds.maxY - corner { return [.top, .left] }
        if point.x > bounds.maxX - corner && point.y > bounds.maxY - corner { return [.top, .right] }
        var edges: HUDResizeEdges = []
        if point.x <= Self.resizeInset { edges.insert(.left) }
        if point.x >= bounds.maxX - Self.resizeInset { edges.insert(.right) }
        if point.y <= Self.resizeInset { edges.insert(.bottom) }
        if point.y >= bounds.maxY - Self.resizeInset { edges.insert(.top) }
        return edges
    }

    private func resizeCursor(for edges: HUDResizeEdges) -> NSCursor {
        let position: NSCursor.FrameResizePosition
        switch edges {
        case [.top, .left]: position = .topLeft
        case [.top, .right]: position = .topRight
        case [.bottom, .left]: position = .bottomLeft
        case [.bottom, .right]: position = .bottomRight
        case .top: position = .top
        case .bottom: position = .bottom
        case .left: position = .left
        default: position = .right
        }
        return NSCursor.frameResize(position: position, directions: .all)
    }

    private func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), max(lower, upper))
    }
}

#Preview("CC HUD — single caption") {
    CCHUDView(
        captions: [
            Caption(
                source: .system,
                text: "We used Redis with a 60-second TTL on hot keys.",
                language: .en,
                isFinal: false
            )
        ],
        backgroundOpacity: 0.7
    )
    .frame(width: 800, height: 110)
    .padding()
    .background(.green.gradient)
}

#Preview("CC HUD — two captions") {
    CCHUDView(
        captions: [
            Caption(
                source: .system,
                text: "And tell me how the cache layer is set up in your backend.",
                language: .en,
                isFinal: true
            ),
            Caption(
                source: .system,
                text: "We used Redis with a 60-second TTL on hot keys and a cron job that refreshed them every minute.",
                language: .en,
                isFinal: false
            )
        ],
        backgroundOpacity: 0.7
    )
    .frame(width: 800, height: 130)
    .padding()
    .background(.green.gradient)
}
