import AppKit
import NativeSmartScribeCore
import SwiftUI

@MainActor
final class HotkeySessionOverlayManager {
    enum Mode {
        case listening
        case processing

        func tint(for style: OverlayHUDStyle) -> Color {
            switch (style, self) {
            case (.capsule, .listening):
                .red
            case (.capsule, .processing):
                .green
            case (.tech, .listening):
                Color(red: 1.0, green: 0.72, blue: 0.16)
            case (.tech, .processing):
                Color(red: 0.20, green: 0.82, blue: 1.0)
            case (.vertical, _):
                .white
            }
        }
    }

    private let state = OverlayState()
    private var panel: DraggableOverlayPanel?
    private var originChangeHandler: ((OverlayHUDOrigin) -> Void)?
    private var languageTapHandler: (() -> Void)?
    private var targetTapHandler: (() -> Void)?
    private var scrollHandler: ((_ deltaY: CGFloat) -> Void)?

    func show(
        mode: Mode,
        settings: OverlayHUDSettings,
        languageMode: TranscriptionLanguageMode = .auto,
        hotkeyTarget: HotkeyTarget = .note,
        targetLanguageLabel: String = "E",
        showsControls: Bool = false,
        languageControlEnabled: Bool = true,
        onOriginChange: ((OverlayHUDOrigin) -> Void)? = nil,
        onLanguageTap: (() -> Void)? = nil,
        onTargetTap: (() -> Void)? = nil,
        onScroll: ((_ deltaY: CGFloat) -> Void)? = nil
    ) {
        let styleChanged = state.style != settings.style
        let modeChanged = state.mode != mode
        state.isVisible = true
        state.mode = mode
        state.scale = settings.scale
        state.style = settings.style
        state.capsuleOpacity = settings.capsuleOpacity
        state.languageMode = languageMode
        state.hotkeyTarget = hotkeyTarget
        state.targetLanguageLabel = targetLanguageLabel
        state.showsControls = showsControls
        state.languageControlEnabled = languageControlEnabled
        if mode == .processing || settings.style != .vertical {
            state.dragOffset = .zero
        }

        let panel = panel ?? makePanel()
        self.panel = panel
        self.originChangeHandler = onOriginChange
        self.languageTapHandler = onLanguageTap
        self.targetTapHandler = onTargetTap
        self.scrollHandler = onScroll
        panel.updateControlsVisibility(showsControls)
        panel.prepareForDisplay(
            settings: settings,
            restoreStoredOrigin: styleChanged,
            animated: modeChanged && !styleChanged
        )
        panel.orderFrontRegardless()
    }

    func update(
        mode: Mode? = nil,
        spectrumBands: [Float]? = nil,
        settings: OverlayHUDSettings? = nil,
        languageMode: TranscriptionLanguageMode? = nil,
        hotkeyTarget: HotkeyTarget? = nil,
        targetLanguageLabel: String? = nil,
        showsControls: Bool? = nil,
        languageControlEnabled: Bool? = nil
    ) {
        if let mode {
            let modeChanged = state.mode != mode
            state.mode = mode
            if mode == .processing {
                state.dragOffset = .zero
            }
            if modeChanged {
                panel?.updateLayout(
                    settings: OverlayHUDSettings(
                        scale: state.scale,
                        capsuleOpacity: state.capsuleOpacity,
                        style: state.style
                    ),
                    restoreStoredOrigin: false,
                    animated: true
                )
            }
        }
        if let spectrumBands, !spectrumBands.isEmpty {
            state.spectrumBands = spectrumBands
        }
        if let settings {
            let styleChanged = state.style != settings.style
            state.scale = settings.scale
            state.style = settings.style
            state.capsuleOpacity = settings.capsuleOpacity
            panel?.updateLayout(
                settings: settings,
                restoreStoredOrigin: styleChanged
            )
        }
        if let languageMode {
            state.languageMode = languageMode
        }
        if let hotkeyTarget {
            state.hotkeyTarget = hotkeyTarget
        }
        if let targetLanguageLabel {
            state.targetLanguageLabel = targetLanguageLabel
        }
        if let showsControls {
            state.showsControls = showsControls
            panel?.updateControlsVisibility(showsControls)
        }
        if let languageControlEnabled {
            state.languageControlEnabled = languageControlEnabled
        }
    }

    func hide() {
        state.isVisible = false
        state.dragOffset = .zero
        panel?.orderOut(nil)
    }

    func playCue(_ cue: AudioCuePlayer.Cue, settings: OverlayHUDSettings) {
        AudioCuePlayer.shared.play(cue, settings: settings)
    }

    /// Current on-screen frame of the HUD panel, used to anchor the provider
    /// quick switcher. Nil while the HUD is hidden.
    func currentHUDFrame() -> NSRect? {
        guard state.isVisible, let panel else { return nil }
        return panel.frame
    }

    private func makePanel() -> DraggableOverlayPanel {
        let panel = DraggableOverlayPanel(
            overlayState: state,
            initialSize: OverlayHUDLayout.panelSize(
                for: state.scale,
                style: state.style,
                mode: state.mode
            )
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.originDidChange = { [weak self] origin in
            self?.originChangeHandler?(origin)
        }
        panel.onLeftTap = { [weak self] in
            guard self?.state.languageControlEnabled == true else { return }
            self?.languageTapHandler?()
        }
        panel.onRightTap = { [weak self] in
            self?.targetTapHandler?()
        }
        panel.onScroll = { [weak self] delta in
            self?.scrollHandler?(delta)
        }
        panel.updateControlsVisibility(state.showsControls)
        return panel
    }
}

@MainActor
private final class OverlayState: ObservableObject {
    @Published var mode: HotkeySessionOverlayManager.Mode = .listening
    @Published var spectrumBands: [Float] = Array(repeating: 0.04, count: 40)
    @Published var scale: Double = 1
    @Published var capsuleOpacity: Double = 0.32
    @Published var style: OverlayHUDStyle = .capsule
    @Published var languageMode: TranscriptionLanguageMode = .auto
    @Published var hotkeyTarget: HotkeyTarget = .note
    @Published var targetLanguageLabel: String = "E"
    @Published var showsControls: Bool = false
    @Published var languageControlEnabled: Bool = true
    @Published var isVisible: Bool = false
    @Published var dragOffset: CGSize = .zero
}

/// Shared layout constants so the SwiftUI rendering and the AppKit hit-testing
/// of the HUD control buttons stay perfectly aligned. The two circular control
/// buttons live *inside* the capsule at its inner edges, with the minimal
/// spectrum sitting between them.
private enum OverlayHUDLayout {
    static let baseWidth: CGFloat = 142
    static let baseHeight: CGFloat = 42
    static let shadowPad: CGFloat = 6
    static let capsuleHPad: CGFloat = 3
    static let controlButtonDiameter: CGFloat = 24
    static let buttonSpectrumGap: CGFloat = 6
    static let classicButtonSpectrumGap: CGFloat = 2.5
    static let techButtonSpectrumGap: CGFloat = 3
    static let verticalButtonSpectrumGap: CGFloat = 3

    static let minScale: Double = 0.8
    static let maxScale: Double = 1.6

    /// Below 100%, the HUD contracts gently. Above 100%, it gains useful
    /// waveform space mostly along its primary axis instead of being uniformly
    /// magnified. This keeps controls readable without producing an oversized
    /// floating panel.
    static func panelSize(
        for scale: Double,
        style: OverlayHUDStyle,
        mode: HotkeySessionOverlayManager.Mode
    ) -> CGSize {
        let below = CGFloat(normalized(scale, from: minScale, to: 1))
        let above = CGFloat(smoothStep(normalized(scale, from: 1, to: maxScale)))

        let listeningSize: CGSize
        switch style {
        case .capsule:
            if scale <= 1 {
                listeningSize = CGSize(width: 94 + 6 * below, height: 38 + 6 * below)
            } else {
                listeningSize = CGSize(width: 100 + 54 * above, height: 44 + 8 * above)
            }
        case .tech:
            if scale <= 1 {
                listeningSize = CGSize(width: 105 + 13 * below, height: 40 + 6 * below)
            } else {
                listeningSize = CGSize(width: 118 + 42 * above, height: 46 + 8 * above)
            }
        case .vertical:
            if scale <= 1 {
                listeningSize = CGSize(width: 52 + 2 * below, height: 100 + 14 * below)
            } else {
                listeningSize = CGSize(width: 54 + 6 * above, height: 114 + 27 * above)
            }
        }

        guard mode == .processing else {
            return listeningSize
        }

        switch style {
        case .capsule:
            let processingWidth =
                classicProcessingSpectrumWidth(for: scale)
                + 20 * visualScale(for: scale)
            return CGSize(width: processingWidth, height: listeningSize.height)
        case .tech:
            let processingWidth =
                techSpectrumWidth(for: scale)
                + 22 * visualScale(for: scale)
            return CGSize(width: processingWidth, height: listeningSize.height)
        case .vertical:
            let processingHeight =
                verticalSpectrumHeight(for: scale)
                + 20 * visualScale(for: scale)
            return CGSize(width: listeningSize.width, height: processingHeight)
        }
    }

    static func visualScale(for scale: Double) -> CGFloat {
        if scale <= 1 {
            return CGFloat(0.88 + 0.12 * normalized(scale, from: minScale, to: 1))
        }
        return CGFloat(1 + 0.12 * smoothStep(normalized(scale, from: 1, to: maxScale)))
    }

    static func spectrumBarCount(for scale: Double, style: OverlayHUDStyle) -> Int {
        switch style {
        case .capsule:
            guard scale > 1 else { return 3 }
            let progress = smoothStep(normalized(scale, from: 1, to: maxScale))
            return 3 + Int((6 * progress).rounded())
        case .tech:
            guard scale > 1 else { return 3 }
            let progress = smoothStep(normalized(scale, from: 1, to: maxScale))
            return 3 + Int((4 * progress).rounded())
        case .vertical:
            guard scale > 1 else { return 3 }
            let progress = smoothStep(normalized(scale, from: 1, to: maxScale))
            return 3 + Int((2 * progress).rounded())
        }
    }

    static func controlDiameter(for scale: Double, style: OverlayHUDStyle) -> CGFloat {
        guard style == .capsule else {
            return controlButtonDiameter * visualScale(for: scale)
        }

        if scale <= 1 {
            let progress = CGFloat(normalized(scale, from: minScale, to: 1))
            return 23.5 + 1.5 * progress
        }
        let progress = CGFloat(smoothStep(normalized(scale, from: 1, to: maxScale)))
        return 25 + 3 * progress
    }

    static func classicProcessingSpectrumWidth(for scale: Double) -> CGFloat {
        if scale <= 1 {
            let progress = CGFloat(normalized(scale, from: minScale, to: 1))
            return 44 + 4 * progress
        }
        let progress = CGFloat(smoothStep(normalized(scale, from: 1, to: maxScale)))
        return 48 + 28 * progress
    }

    static func techSpectrumWidth(for scale: Double) -> CGFloat {
        if scale <= 1 {
            let progress = CGFloat(normalized(scale, from: minScale, to: 1))
            return 38 + 4 * progress
        }
        let progress = CGFloat(smoothStep(normalized(scale, from: 1, to: maxScale)))
        return 42 + 30 * progress
    }

    static func verticalSpectrumHeight(for scale: Double) -> CGFloat {
        if scale <= 1 {
            let progress = CGFloat(normalized(scale, from: minScale, to: 1))
            return 34 + 6 * progress
        }
        let progress = CGFloat(smoothStep(normalized(scale, from: 1, to: maxScale)))
        return 40 + 18 * progress
    }

    private static func normalized(_ value: Double, from lower: Double, to upper: Double) -> Double {
        guard upper > lower else { return 0 }
        return min(1, max(0, (value - lower) / (upper - lower)))
    }

    private static func smoothStep(_ value: Double) -> Double {
        value * value * (3 - 2 * value)
    }

    /// Visual frames of the left (language) and right (target) control buttons
    /// expressed in the coordinate space of the overlay content view.
    static func controlButtonFrames(
        in bounds: CGRect,
        scale rawScale: Double,
        style: OverlayHUDStyle
    ) -> (left: CGRect, right: CGRect) {
        let scale = visualScale(for: rawScale)
        let diameter = controlDiameter(for: rawScale, style: style)
        let inset =
            (shadowPad + (style == .capsule ? 4 : 5))
            * scale

        switch style {
        case .capsule:
            let centerY = bounds.midY
            return (
                CGRect(
                    x: bounds.minX + inset,
                    y: centerY - diameter / 2,
                    width: diameter,
                    height: diameter
                ),
                CGRect(
                    x: bounds.maxX - inset - diameter,
                    y: centerY - diameter / 2,
                    width: diameter,
                    height: diameter
                )
            )
        case .tech:
            let centerY = bounds.midY
            return (
                CGRect(
                    x: bounds.minX + inset,
                    y: centerY - diameter / 2,
                    width: diameter,
                    height: diameter
                ),
                CGRect(
                    x: bounds.maxX - inset - diameter,
                    y: centerY - diameter / 2,
                    width: diameter,
                    height: diameter
                )
            )
        case .vertical:
            let x = bounds.midX - diameter / 2
            return (
                CGRect(
                    x: x,
                    y: bounds.maxY - inset - diameter,
                    width: diameter,
                    height: diameter
                ),
                CGRect(x: x, y: bounds.minY + inset, width: diameter, height: diameter)
            )
        }
    }

    /// Slightly enlarged frames used for tap hit-testing to make the small
    /// circular buttons easier to hit.
    static func controlButtonHitFrames(
        in bounds: CGRect,
        scale: Double,
        style: OverlayHUDStyle
    ) -> (left: CGRect, right: CGRect) {
        let frames = controlButtonFrames(in: bounds, scale: scale, style: style)
        return (
            frames.left.insetBy(dx: -6, dy: -6),
            frames.right.insetBy(dx: -6, dy: -6)
        )
    }
}

private final class DraggableOverlayPanel: NSPanel {
    var originDidChange: ((OverlayHUDOrigin) -> Void)?
    var onLeftTap: (() -> Void)? {
        get { rootView.onLeftTap }
        set { rootView.onLeftTap = newValue }
    }
    var onRightTap: (() -> Void)? {
        get { rootView.onRightTap }
        set { rootView.onRightTap = newValue }
    }
    var onScroll: ((_ deltaY: CGFloat) -> Void)? {
        get { rootView.onScroll }
        set { rootView.onScroll = newValue }
    }

    private let overlayState: OverlayState
    private let rootView: OverlayRootView
    private var hasPlacedFrame = false
    private var dragStartFrameOrigin: CGPoint?
    private var dragStartMouseLocation: CGPoint?

    init(overlayState: OverlayState, initialSize: CGSize) {
        self.overlayState = overlayState
        self.rootView = OverlayRootView(state: overlayState)
        super.init(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        contentView = rootView
        rootView.translatesAutoresizingMaskIntoConstraints = false
        rootView.onMouseDown = { [weak self] screenPoint in
            self?.beginDrag(at: screenPoint)
        }
        rootView.onMouseDragged = { [weak self] screenPoint in
            self?.updateDrag(to: screenPoint)
        }
        rootView.onMouseUp = { [weak self] in
            self?.endDrag()
        }
        setContentSize(initialSize)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func updateControlsVisibility(_ visible: Bool) {
        rootView.showsControls = visible
    }

    func prepareForDisplay(
        settings: OverlayHUDSettings,
        restoreStoredOrigin: Bool,
        animated: Bool
    ) {
        overlayState.capsuleOpacity = settings.capsuleOpacity
        updateLayout(
            settings: settings,
            restoreStoredOrigin: restoreStoredOrigin,
            animated: animated
        )
        guard !hasPlacedFrame else { return }

        let visibleFrame = screenVisibleFrame()
        let origin =
            settings.origin(for: settings.style).map(CGPoint.init(origin:))
            ?? bottomCenterOrigin(for: frame.size, visibleFrame: visibleFrame)
        setFrameOrigin(clamp(origin: origin, size: frame.size, visibleFrame: visibleFrame))
        hasPlacedFrame = true
    }

    func updateLayout(
        settings: OverlayHUDSettings,
        restoreStoredOrigin: Bool,
        animated: Bool = false
    ) {
        let newSize = OverlayHUDLayout.panelSize(
            for: settings.scale,
            style: settings.style,
            mode: overlayState.mode
        )
        let previousFrame = frame
        let previousCenter = CGPoint(x: previousFrame.midX, y: previousFrame.midY)

        guard hasPlacedFrame else {
            setContentSize(newSize)
            return
        }

        let visibleFrame = screenVisibleFrame()
        let newOrigin: CGPoint
        if restoreStoredOrigin, let storedOrigin = settings.origin(for: settings.style) {
            newOrigin = clamp(
                origin: CGPoint(origin: storedOrigin),
                size: newSize,
                visibleFrame: visibleFrame
            )
        } else {
            let centeredOrigin = CGPoint(
                x: previousCenter.x - newSize.width / 2,
                y: previousCenter.y - newSize.height / 2
            )
            newOrigin = clamp(
                origin: centeredOrigin,
                size: newSize,
                visibleFrame: visibleFrame
            )
        }

        let newFrame = CGRect(origin: newOrigin, size: newSize)
        guard animated, isVisible else {
            setFrame(newFrame, display: true)
            persistCurrentOrigin()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(newFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.persistCurrentOrigin()
            }
        }
    }

    private func beginDrag(at screenPoint: CGPoint) {
        overlayState.dragOffset = .zero
        dragStartMouseLocation = screenPoint
        dragStartFrameOrigin = frame.origin
    }

    private func updateDrag(to screenPoint: CGPoint) {
        guard let dragStartMouseLocation, let dragStartFrameOrigin else { return }
        let visibleFrame = screenVisibleFrame()
        let delta = CGPoint(
            x: screenPoint.x - dragStartMouseLocation.x,
            y: screenPoint.y - dragStartMouseLocation.y
        )
        let proposedOrigin = CGPoint(
            x: dragStartFrameOrigin.x + delta.x,
            y: dragStartFrameOrigin.y + delta.y
        )
        if overlayState.style == .vertical, overlayState.mode == .listening {
            overlayState.dragOffset = CGSize(
                width: min(7, max(-7, -delta.x * 0.08)),
                height: min(4.5, max(-4.5, delta.y * 0.045))
            )
        }
        setFrameOrigin(clamp(origin: proposedOrigin, size: frame.size, visibleFrame: visibleFrame))
    }

    private func endDrag() {
        dragStartMouseLocation = nil
        dragStartFrameOrigin = nil
        overlayState.dragOffset = .zero
        persistCurrentOrigin()
    }

    private func persistCurrentOrigin() {
        originDidChange?(OverlayHUDOrigin(x: Double(frame.origin.x), y: Double(frame.origin.y)))
    }

    private func screenVisibleFrame() -> CGRect {
        screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
    }
}

private final class OverlayRootView: NSView {
    var onMouseDown: ((CGPoint) -> Void)?
    var onMouseDragged: ((CGPoint) -> Void)?
    var onMouseUp: (() -> Void)?
    var onScroll: ((_ deltaY: CGFloat) -> Void)?
    var onLeftTap: (() -> Void)? {
        get { captureView.onLeftTap }
        set { captureView.onLeftTap = newValue }
    }
    var onRightTap: (() -> Void)? {
        get { captureView.onRightTap }
        set { captureView.onRightTap = newValue }
    }
    var showsControls: Bool = false {
        didSet { captureView.showsControls = showsControls }
    }

    private let hostingView: NSHostingView<HotkeySessionOverlayView>
    private let captureView = OverlayMouseCaptureView()

    init(state: OverlayState) {
        hostingView = NSHostingView(rootView: HotkeySessionOverlayView(state: state))
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = .clear

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        captureView.translatesAutoresizingMaskIntoConstraints = false
        captureView.onMouseDown = { [weak self] point in self?.onMouseDown?(point) }
        captureView.onMouseDragged = { [weak self] point in self?.onMouseDragged?(point) }
        captureView.onMouseUp = { [weak self] in self?.onMouseUp?() }
        captureView.onScroll = { [weak self] delta in self?.onScroll?(delta) }
        captureView.controlFramesProvider = { [weak state] bounds in
            guard let state else {
                return OverlayHUDLayout.controlButtonHitFrames(
                    in: bounds,
                    scale: 1,
                    style: .capsule
                )
            }
            return OverlayHUDLayout.controlButtonHitFrames(
                in: bounds,
                scale: state.scale,
                style: state.style
            )
        }

        addSubview(hostingView)
        addSubview(captureView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
            captureView.leadingAnchor.constraint(equalTo: leadingAnchor),
            captureView.trailingAnchor.constraint(equalTo: trailingAnchor),
            captureView.topAnchor.constraint(equalTo: topAnchor),
            captureView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class OverlayMouseCaptureView: NSView {
    var onMouseDown: ((CGPoint) -> Void)?
    var onMouseDragged: ((CGPoint) -> Void)?
    var onMouseUp: (() -> Void)?
    var onLeftTap: (() -> Void)?
    var onRightTap: (() -> Void)?
    var onScroll: ((_ deltaY: CGFloat) -> Void)?
    var showsControls = false
    var controlFramesProvider: ((CGRect) -> (left: CGRect, right: CGRect))?

    /// Movement (in view points) beyond which a press becomes a drag instead of a tap.
    private static let dragThreshold: CGFloat = 4

    private var downScreenPoint: CGPoint?
    private var downViewPoint: CGPoint?
    private var didDrag = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        downScreenPoint = NSEvent.mouseLocation
        downViewPoint = convert(event.locationInWindow, from: nil)
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downScreenPoint, let downViewPoint else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let distance = hypot(viewPoint.x - downViewPoint.x, viewPoint.y - downViewPoint.y)

        if !didDrag, distance > Self.dragThreshold {
            didDrag = true
            // Begin dragging from the original press location so the window
            // does not jump when the threshold is first exceeded.
            onMouseDown?(downScreenPoint)
        }

        if didDrag {
            onMouseDragged?(NSEvent.mouseLocation)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let wasDrag = didDrag
        let tapPoint = downViewPoint
        downScreenPoint = nil
        downViewPoint = nil
        didDrag = false

        if wasDrag {
            onMouseUp?()
        } else if let tapPoint {
            handleTap(at: tapPoint)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        // Normalize line-based mouse-wheel deltas so one notch maps to one
        // discrete step; trackpads already deliver precise pixel deltas.
        let delta = event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY
            : event.scrollingDeltaY * ProviderQuickSwitcherModel.defaultStepThreshold
        if abs(delta) > 0.001 {
            onScroll?(delta)
        }
    }

    private func handleTap(at point: CGPoint) {
        guard showsControls else { return }
        let hitFrames =
            controlFramesProvider?(bounds)
            ?? OverlayHUDLayout.controlButtonHitFrames(
                in: bounds,
                scale: 1,
                style: .capsule
            )
        if hitFrames.left.contains(point) {
            onLeftTap?()
        } else if hitFrames.right.contains(point) {
            onRightTap?()
        }
    }
}

private struct HotkeySessionOverlayView: View {
    @ObservedObject var state: OverlayState

    var body: some View {
        hudContent
            .frame(
                width: max(1, panelSize.width - shadowInset * 2),
                height: max(1, panelSize.height - shadowInset * 2)
            )
            .padding(shadowInset)
            .frame(width: panelSize.width, height: panelSize.height)
    }

    private var hudContent: some View {
        layoutContent
            .padding(contentPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if state.style != .vertical {
                    ZStack {
                        containerShape
                            .fill(.ultraThinMaterial)
                        containerShape
                            .fill(surfaceGradient)
                        containerShape
                            .fill(
                                RadialGradient(
                                    colors: [tint.opacity(0.16), .clear],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 84 * visualScale
                                )
                            )
                    }
                    .opacity(state.capsuleOpacity)
                }
            }
            .overlay {
                if state.style != .vertical {
                    containerShape
                        .stroke(.white.opacity(0.24), lineWidth: 1.0 * visualScale)
                }
            }
            .overlay {
                if state.style != .vertical {
                    containerShape
                        .stroke(.black.opacity(0.08), lineWidth: 0.7 * visualScale)
                        .padding(2 * visualScale)
                }
            }
            .shadow(
                color: state.style == .vertical
                    ? .clear
                    : tint.opacity(state.style == .capsule ? 0.08 : 0.14),
                radius: 12 * visualScale,
                x: 0,
                y: 4 * visualScale
            )
            .shadow(
                color: state.style == .vertical ? .clear : .black.opacity(0.18),
                radius: 14 * visualScale,
                x: 0,
                y: 6
            )
            .animation(.easeInOut(duration: 0.24), value: state.style)
            .animation(.easeInOut(duration: 0.2), value: state.showsControls)
            .animation(.easeInOut(duration: 0.2), value: state.mode)
            .animation(
                .spring(response: 0.36, dampingFraction: 0.52, blendDuration: 0.04),
                value: state.dragOffset
            )
    }

    @ViewBuilder
    private var layoutContent: some View {
        switch state.style {
        case .capsule:
            if state.mode == .processing {
                classicSpectrum(barCount: classicProcessingBarCount)
                    .frame(
                        width: OverlayHUDLayout.classicProcessingSpectrumWidth(
                            for: state.scale
                        )
                    )
                    .frame(maxHeight: .infinity)
            } else {
                HStack(spacing: OverlayHUDLayout.classicButtonSpectrumGap * visualScale) {
                    controlSlot(
                        label: state.languageMode == .auto ? "A" : state.targetLanguageLabel,
                        isActive: state.languageMode == .target,
                        isEnabled: state.languageControlEnabled
                    )

                    classicSpectrum(barCount: spectrumBarCount)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    controlSlot(
                        label: state.hotkeyTarget.hudLabel,
                        isActive: state.hotkeyTarget != .raw
                    )
                }
            }
        case .tech:
            if state.mode == .processing {
                techSpectrum
                    .frame(width: OverlayHUDLayout.techSpectrumWidth(for: state.scale))
                    .frame(maxHeight: .infinity)
            } else {
                HStack(spacing: OverlayHUDLayout.techButtonSpectrumGap * visualScale) {
                    controlSlot(
                        label: state.languageMode == .auto ? "A" : state.targetLanguageLabel,
                        isActive: state.languageMode == .target,
                        isEnabled: state.languageControlEnabled
                    )

                    techSpectrum
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    controlSlot(
                        label: state.hotkeyTarget.hudLabel,
                        isActive: state.hotkeyTarget != .raw
                    )
                }
            }
        case .vertical:
            if state.mode == .processing {
                verticalSpectrum
                    .frame(height: OverlayHUDLayout.verticalSpectrumHeight(for: state.scale))
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: OverlayHUDLayout.verticalButtonSpectrumGap * visualScale) {
                    controlSlot(
                        label: state.languageMode == .auto ? "A" : state.targetLanguageLabel,
                        isActive: state.languageMode == .target,
                        isEnabled: state.languageControlEnabled
                    )

                    verticalSpectrum
                        .frame(height: OverlayHUDLayout.verticalSpectrumHeight(for: state.scale))
                        .frame(maxWidth: .infinity)
                        .scaleEffect(y: verticalDragStretch, anchor: .top)

                    controlSlot(
                        label: state.hotkeyTarget.hudLabel,
                        isActive: state.hotkeyTarget != .raw
                    )
                    .offset(
                        x: state.dragOffset.width,
                        y: state.dragOffset.height
                    )
                }
            }
        }
    }

    private var containerShape: AnyShape {
        switch state.style {
        case .capsule:
            AnyShape(Capsule(style: .continuous))
        case .tech:
            AnyShape(
                RoundedRectangle(
                    cornerRadius: 11 * visualScale,
                    style: .continuous
                )
            )
        case .vertical:
            AnyShape(Circle())
        }
    }

    private var surfaceGradient: LinearGradient {
        let colors: [Color]
        switch state.style {
        case .capsule:
            colors = [
                .white.opacity(0.16),
                .white.opacity(0.035),
                .black.opacity(0.04),
            ]
        case .tech:
            colors = [
                tint.opacity(0.12),
                .black.opacity(0.08),
                .white.opacity(0.05),
            ]
        case .vertical:
            colors = [
                .white.opacity(0.14),
                .white.opacity(0.025),
                .black.opacity(0.075),
            ]
        }

        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var contentPadding: EdgeInsets {
        switch state.style {
        case .capsule:
            EdgeInsets(
                top: 3.5 * visualScale,
                leading: 4 * visualScale,
                bottom: 3.5 * visualScale,
                trailing: 4 * visualScale
            )
        case .tech:
            EdgeInsets(
                top: 4 * visualScale,
                leading: 5 * visualScale,
                bottom: 4 * visualScale,
                trailing: 5 * visualScale
            )
        case .vertical:
            EdgeInsets(
                top: 4 * visualScale,
                leading: 4 * visualScale,
                bottom: 4 * visualScale,
                trailing: 4 * visualScale
            )
        }
    }

    private var visualScale: CGFloat {
        OverlayHUDLayout.visualScale(for: state.scale)
    }

    private var panelSize: CGSize {
        OverlayHUDLayout.panelSize(
            for: state.scale,
            style: state.style,
            mode: state.mode
        )
    }

    private var shadowInset: CGFloat {
        OverlayHUDLayout.shadowPad * visualScale
    }

    private var tint: Color {
        state.mode.tint(for: state.style)
    }

    private var spectrumBarCount: Int {
        OverlayHUDLayout.spectrumBarCount(
            for: state.scale,
            style: state.style
        )
    }

    private var classicProcessingBarCount: Int {
        max(7, spectrumBarCount + 2)
    }

    private func classicSpectrum(barCount: Int) -> some View {
        MinimalBarSpectrumView(
            bands: state.spectrumBands,
            color: tint,
            isActive: true,
            isVisible: state.isVisible,
            isProcessing: state.mode == .processing,
            barCount: barCount
        )
    }

    private var techSpectrum: some View {
        EnergyZigzagSpectrumView(
            bands: state.spectrumBands,
            color: tint,
            isVisible: state.isVisible,
            isProcessing: state.mode == .processing
        )
    }

    private var verticalSpectrum: some View {
        VerticalPulseSpectrumView(
            bands: state.spectrumBands,
            color: tint,
            isVisible: state.isVisible,
            isProcessing: state.mode == .processing,
            segmentCount: max(5, spectrumBarCount),
            dragOffset: state.mode == .listening ? state.dragOffset : .zero
        )
    }

    private var verticalDragStretch: CGFloat {
        guard state.style == .vertical, state.mode == .listening else { return 1 }
        let magnitude = sqrt(
            state.dragOffset.width * state.dragOffset.width
                + state.dragOffset.height * state.dragOffset.height
        )
        return 1 + min(0.08, magnitude * 0.012)
    }

    private var controlDiameter: CGFloat {
        OverlayHUDLayout.controlDiameter(
            for: state.scale,
            style: state.style
        )
    }

    private var controlTextScale: CGFloat {
        controlDiameter / OverlayHUDLayout.controlButtonDiameter
    }

    @ViewBuilder
    private func controlSlot(
        label: String,
        isActive: Bool,
        isEnabled: Bool = true
    ) -> some View {
        if state.showsControls {
            controlButton(label: label, isActive: isActive)
                .opacity(isEnabled ? 1 : 0.34)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
        } else {
            Color.clear
                .frame(
                    width: controlDiameter,
                    height: controlDiameter
                )
        }
    }

    private func controlButton(label: String, isActive: Bool) -> some View {
        let xOffset: CGFloat = (label == "1" ? 0.35 : 0) * visualScale
        let yOffset: CGFloat = (0.65 + (state.style == .vertical ? 0.35 : 0)) * visualScale

        return ZStack {
            Text(label)
                .font(
                    .system(
                        size: 12 * controlTextScale,
                        weight: .semibold,
                        design: state.style == .vertical ? .monospaced : .rounded
                    )
                )
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.center)
                .offset(x: xOffset, y: yOffset)
        }
        .frame(width: controlDiameter, height: controlDiameter, alignment: .center)
        .background {
            controlShape.fill(.ultraThinMaterial)
        }
        .background {
            controlShape.fill(
                tint.opacity(isActive ? 0.20 : 0.05)
            )
        }
        .overlay {
            controlShape
                .stroke(
                    .white.opacity(isActive ? 0.88 : 0.42),
                    lineWidth: 1.0 * visualScale
                )
        }
        .shadow(
            color: state.style == .vertical ? .clear : tint.opacity(0.18),
            radius: 5 * visualScale,
            x: 0,
            y: 2
        )
    }

    private var controlShape: AnyShape {
        switch state.style {
        case .capsule:
            AnyShape(Circle())
        case .tech:
            AnyShape(
                RoundedRectangle(
                    cornerRadius: 6 * visualScale,
                    style: .continuous
                )
            )
        case .vertical:
            AnyShape(Circle())
        }
    }
}

/// Minimal equalizer-style spectrum for the hotkey HUD: a small set of vertical
/// rounded bars centered in the available width. While listening it mirrors the
/// live microphone spectrum; while processing it renders a symmetric travelling
/// wave so the user can see that polishing is in progress.
private struct MinimalBarSpectrumView: View {
    let bands: [Float]
    let color: Color
    let isActive: Bool
    let isVisible: Bool
    let isProcessing: Bool
    var barCount: Int = 5
    var noiseFloor: CGFloat = 0.10
    var processingSpeed: CGFloat = 1.1

    @State private var phase: TimeInterval = Date().timeIntervalSinceReferenceDate

    private let animationTimer = Timer.publish(
        every: 1.0 / 45.0,
        on: .main,
        in: .common
    ).autoconnect()

    private var values: [CGFloat] {
        if isProcessing {
            return (0..<barCount).map { index in
                processingValue(at: index, phase: phase)
            }
        }

        if isActive {
            return HUDSpectrumResponse.classicListeningValues(
                bands: bands,
                barCount: barCount,
                noiseFloor: Float(noiseFloor)
            )
            .map { CGFloat($0) }
        }

        return Array(repeating: noiseFloor, count: barCount)
    }

    private func processingValue(at index: Int, phase: TimeInterval) -> CGFloat {
        let t = CGFloat(index) / CGFloat(max(barCount - 1, 1))
        let envelope = 0.45 + 0.55 * sin(t * .pi)
        let travel = phase * processingSpeed - CGFloat(index) * 0.9
        let carrier = 0.5 + 0.5 * sin(travel * .pi * 2.0)
        let harmonic = 0.5 + 0.5 * sin(travel * .pi * 4.0 + 1.1)
        let synthetic = 0.30 + 0.50 * carrier + 0.20 * harmonic
        return min(1, max(noiseFloor, synthetic * envelope + 0.12))
    }

    var body: some View {
        Canvas { context, size in
            drawBars(in: &context, size: size)
        }
        .onAppear { phase = Date().timeIntervalSinceReferenceDate }
        .onReceive(animationTimer) { date in
            guard isVisible, isProcessing else { return }
            phase = date.timeIntervalSinceReferenceDate
        }
    }

    private func drawBars(in context: inout GraphicsContext, size: CGSize) {
        let resolved = values
        let count = resolved.count
        guard count > 0, size.width > 0, size.height > 0 else { return }

        // Adaptive bar sizing: bars are proportional to the height, but shrink
        // to fit whenever many bars are requested so the equalizer never
        // overflows the available width or collapses into a single blob.
        let preferredBarWidth = max(3.6, size.height * 0.15)
        let preferredGap = max(3.4, preferredBarWidth * 0.9)
        let preferredTotal = preferredBarWidth * CGFloat(count) + preferredGap * CGFloat(count - 1)
        let fit = preferredTotal > size.width ? size.width / preferredTotal : 1
        let barWidth = max(2.8, preferredBarWidth * fit)
        let gap = preferredGap * fit
        let totalWidth = barWidth * CGFloat(count) + gap * CGFloat(count - 1)
        let startX = (size.width - totalWidth) / 2
        let centerY = size.height / 2
        let maxHeight = size.height * 0.82
        let minHeight = size.height * 0.14
        let cornerRadius = barWidth / 2

        for (index, value) in resolved.enumerated() {
            let height = max(minHeight, value * maxHeight)
            let x = startX + CGFloat(index) * (barWidth + gap)
            let rect = CGRect(x: x, y: centerY - height / 2, width: barWidth, height: height)
            let barPath = Path(roundedRect: rect, cornerRadius: cornerRadius)

            var glowContext = context
            glowContext.addFilter(.blur(radius: barWidth * 0.5))
            glowContext.fill(barPath, with: .color(color.opacity(isActive ? 0.28 : 0.14)))

            context.fill(
                barPath,
                with: .linearGradient(
                    Gradient(colors: [
                        color.opacity(0.45),
                        color.opacity(0.98),
                        color.opacity(0.45)
                    ]),
                    startPoint: CGPoint(x: rect.midX, y: rect.minY),
                    endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                )
            )

            if height > minHeight * 1.8 {
                let highlight = Path(
                    roundedRect: rect.insetBy(dx: barWidth * 0.28, dy: height * 0.16),
                    cornerRadius: max(0.5, cornerRadius - barWidth * 0.28)
                )
                context.fill(highlight, with: .color(.white.opacity(isActive ? 0.18 : 0.08)))
            }
        }
    }
}

/// A deliberately technical alternative to the classic equalizer. The live
/// signal is rendered as a connected, angular energy trace with travelling
/// phase and luminous node markers instead of a row of ordinary bars.
private struct EnergyZigzagSpectrumView: View {
    let bands: [Float]
    let color: Color
    let isVisible: Bool
    let isProcessing: Bool

    @State private var phase = Date().timeIntervalSinceReferenceDate

    private let animationTimer = Timer.publish(
        every: 1.0 / 36.0,
        on: .main,
        in: .common
    ).autoconnect()

    var body: some View {
        Canvas { context, size in
            drawCenterLine(in: &context, size: size)
            drawEnergyTrace(in: &context, size: size)
        }
        .onReceive(animationTimer) { date in
            guard isVisible else { return }
            phase = date.timeIntervalSinceReferenceDate
        }
        .accessibilityHidden(true)
    }

    private var signalValues: [CGFloat] {
        let pointCount = 9
        if isProcessing {
            return (0..<pointCount).map { index in
                let offset = phase * 4.2 - Double(index) * 0.74
                let primary = 0.5 + 0.5 * sin(offset)
                let harmonic = 0.5 + 0.5 * sin(offset * 1.9 + 0.8)
                return 0.20 + 0.55 * CGFloat(primary) + 0.25 * CGFloat(harmonic)
            }
        }

        let resampled = resample(bands, count: pointCount)
        let peak = resampled.max() ?? 0
        guard peak >= 0.10 else {
            return (0..<pointCount).map { index in
                0.10 + 0.025 * sin(CGFloat(index) * 1.35 + CGFloat(phase * 1.7))
            }
        }
        return resampled.map { value in
            let cleaned = max(0, (value - 0.10) / 0.90)
            return max(0.12, min(1, pow(cleaned * 2.15, 0.78)))
        }
    }

    private func drawCenterLine(in context: inout GraphicsContext, size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }

        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height / 2))
        path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        context.stroke(
            path,
            with: .color(.white.opacity(0.08)),
            style: StrokeStyle(lineWidth: 0.6, dash: [2.5, 3.5])
        )
    }

    private func drawEnergyTrace(in context: inout GraphicsContext, size: CGSize) {
        let values = signalValues
        guard values.count > 1, size.width > 0, size.height > 0 else { return }

        let horizontalInset: CGFloat = 2
        let usableWidth = max(1, size.width - horizontalInset * 2)
        let midY = size.height / 2
        let amplitude = size.height * 0.36
        var points: [CGPoint] = []

        for (index, value) in values.enumerated() {
            let t = CGFloat(index) / CGFloat(values.count - 1)
            let x = horizontalInset + usableWidth * t
            let polarity: CGFloat = index.isMultiple(of: 2) ? -1 : 1
            let traveling = sin(CGFloat(phase * 2.8) + t * .pi * 2.1) * 0.18
            let y = midY + polarity * amplitude * min(1, value + traveling)
            points.append(CGPoint(x: x, y: y))
        }

        var trace = Path()
        trace.move(to: points[0])
        for point in points.dropFirst() {
            trace.addLine(to: point)
        }

        var glow = context
        glow.addFilter(.blur(radius: 4.5))
        glow.stroke(
            trace,
            with: .color(color.opacity(0.48)),
            style: StrokeStyle(lineWidth: 4.4, lineCap: .square, lineJoin: .miter)
        )
        context.stroke(
            trace,
            with: .linearGradient(
                Gradient(colors: [
                    color.opacity(0.45),
                    color,
                    .white.opacity(0.92),
                    color,
                    color.opacity(0.45),
                ]),
                startPoint: CGPoint(x: 0, y: midY),
                endPoint: CGPoint(x: size.width, y: midY)
            ),
            style: StrokeStyle(lineWidth: 1.6, lineCap: .square, lineJoin: .miter)
        )

        for (index, point) in points.enumerated() where index.isMultiple(of: 2) {
            let nodeSize: CGFloat = isProcessing ? 3.2 : 2.6
            let nodeRect = CGRect(
                x: point.x - nodeSize / 2,
                y: point.y - nodeSize / 2,
                width: nodeSize,
                height: nodeSize
            )
            context.fill(
                Path(roundedRect: nodeRect, cornerRadius: 0.8),
                with: .color(index == points.count / 2 ? .white : color)
            )
        }
    }
}

/// A shell-free monochrome HUD. Listening is shown as a column of responsive
/// white spheres; processing switches to a moving double helix so the two
/// states remain unmistakable without relying on color.
private struct VerticalPulseSpectrumView: View {
    let bands: [Float]
    let color: Color
    let isVisible: Bool
    let isProcessing: Bool
    let segmentCount: Int
    let dragOffset: CGSize

    @State private var phase = Date().timeIntervalSinceReferenceDate

    private let animationTimer = Timer.publish(
        every: 1.0 / 36.0,
        on: .main,
        in: .common
    ).autoconnect()

    var body: some View {
        Canvas { context, size in
            if isProcessing {
                drawProcessingHelix(in: &context, size: size)
            } else {
                drawListeningSpheres(in: &context, size: size)
            }
        }
        .onReceive(animationTimer) { date in
            guard isVisible else { return }
            phase = date.timeIntervalSinceReferenceDate
        }
        .accessibilityHidden(true)
    }

    private var listeningValues: [CGFloat] {
        let count = max(5, segmentCount)
        let resampled = resample(bands, count: count)
        let peak = resampled.max() ?? 0
        guard peak >= 0.035 else {
            return (0..<count).map { index in
                0.08 + 0.02 * sin(CGFloat(phase * 1.35) + CGFloat(index) * 0.8)
            }
        }
        let global = min(1, pow(max(0, (peak - 0.03) / 0.22), 0.5))
        return resampled.enumerated().map { index, value in
            let local = min(1, pow(max(0, (value - 0.025) / 0.20), 0.58))
            let modulation =
                0.64
                + 0.36 * abs(sin(CGFloat(phase * 1.4) + CGFloat(index) * 0.9))
            return max(0.10, max(local, global * modulation))
        }
    }

    private func drawListeningSpheres(
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        let resolved = listeningValues
        guard !resolved.isEmpty, size.width > 0, size.height > 0 else { return }

        let step = size.height / CGFloat(resolved.count + 1)
        let maximumDiameter = min(7.2, step * 1.05, size.width * 0.26)
        let minimumDiameter = min(2.0, maximumDiameter)
        let centerX = size.width / 2

        var rope = Path()
        rope.move(to: CGPoint(x: centerX, y: 0))
        rope.addCurve(
            to: CGPoint(x: centerX + dragOffset.width, y: size.height),
            control1: CGPoint(
                x: centerX + dragOffset.width * 0.10,
                y: size.height * 0.34
            ),
            control2: CGPoint(
                x: centerX + dragOffset.width * 0.72,
                y: size.height * 0.70
            )
        )
        context.stroke(
            rope,
            with: .color(color.opacity(0.18)),
            style: StrokeStyle(lineWidth: 0.75, lineCap: .round)
        )

        for (index, value) in resolved.enumerated() {
            let progress = CGFloat(index + 1) / CGFloat(resolved.count + 1)
            let ropeInfluence = pow(progress, 1.55)
            let diameter =
                minimumDiameter
                + (maximumDiameter - minimumDiameter) * sqrt(max(0, value))
            let horizontalMotion =
                sin(CGFloat(phase * 4.8) + CGFloat(index) * 1.15)
                * (0.35 + 4.4 * value)
            let verticalMotion =
                cos(CGFloat(phase * 3.9) + CGFloat(index) * 0.82)
                * (0.20 + 1.6 * value)
            drawSphere(
                in: &context,
                center: CGPoint(
                    x: centerX + dragOffset.width * ropeInfluence + horizontalMotion,
                    y: step * CGFloat(index + 1)
                        + dragOffset.height * ropeInfluence
                        + verticalMotion
                ),
                diameter: diameter,
                opacity: 0.96
            )
        }
    }

    private func drawProcessingHelix(
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        guard size.width > 0, size.height > 0 else { return }

        let count = max(6, segmentCount + 1)
        let verticalInset: CGFloat = 2.5
        let usableHeight = max(1, size.height - verticalInset * 2)
        let radius = min(7.5, size.width * 0.28)

        for index in 0..<count {
            let progress = CGFloat(index) / CGFloat(max(1, count - 1))
            let y = verticalInset + usableHeight * progress
            let angle = CGFloat(phase * 3.0) + CGFloat(index) * 0.98
            let offset = sin(angle) * radius
            let depth = 0.5 + 0.5 * cos(angle)
            let firstCenter = CGPoint(x: size.width / 2 + offset, y: y)
            let secondCenter = CGPoint(x: size.width / 2 - offset, y: y)

            var connector = Path()
            connector.move(to: firstCenter)
            connector.addLine(to: secondCenter)
            context.stroke(
                connector,
                with: .color(color.opacity(0.10 + 0.08 * depth)),
                lineWidth: 0.7
            )

            drawSphere(
                in: &context,
                center: firstCenter,
                diameter: 2.5 + 1.0 * depth,
                opacity: 0.52 + 0.42 * depth
            )
            drawSphere(
                in: &context,
                center: secondCenter,
                diameter: 3.5 - 1.0 * depth,
                opacity: 0.94 - 0.42 * depth
            )
        }
    }

    private func drawSphere(
        in context: inout GraphicsContext,
        center: CGPoint,
        diameter: CGFloat,
        opacity: CGFloat
    ) {
        let rect = CGRect(
            x: center.x - diameter / 2,
            y: center.y - diameter / 2,
            width: diameter,
            height: diameter
        )
        let sphere = Path(ellipseIn: rect)

        if isProcessing {
            var glow = context
            glow.addFilter(.blur(radius: 1.2))
            glow.fill(sphere, with: .color(color.opacity(0.18 * opacity)))
        }
        context.fill(sphere, with: .color(color.opacity(opacity)))
    }
}

private func resample(_ bands: [Float], count: Int) -> [CGFloat] {
    guard count > 0 else { return [] }
    guard !bands.isEmpty else { return Array(repeating: 0, count: count) }

    return (0..<count).map { index in
        let source =
            Double(index) / Double(max(count - 1, 1))
            * Double(max(bands.count - 1, 0))
        let lower = Int(floor(source))
        let upper = min(lower + 1, bands.count - 1)
        let fraction = CGFloat(source - Double(lower))
        return min(
            1,
            max(
                0,
                CGFloat(bands[lower]) * (1 - fraction)
                    + CGFloat(bands[upper]) * fraction
            )
        )
    }
}

private func bottomCenterOrigin(for size: CGSize, visibleFrame: CGRect) -> CGPoint {
    let inset: CGFloat = 18
    return CGPoint(x: visibleFrame.midX - size.width / 2, y: visibleFrame.minY + inset)
}

private func clamp(origin: CGPoint, size: CGSize, visibleFrame: CGRect) -> CGPoint {
    CGPoint(
        x: min(max(origin.x, visibleFrame.minX + 12), visibleFrame.maxX - size.width - 12),
        y: min(max(origin.y, visibleFrame.minY + 12), visibleFrame.maxY - size.height - 12)
    )
}

private extension CGPoint {
    init(origin: OverlayHUDOrigin) {
        self.init(x: CGFloat(origin.x), y: CGFloat(origin.y))
    }
}
