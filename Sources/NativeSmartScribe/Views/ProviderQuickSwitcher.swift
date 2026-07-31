import AppKit
import NativeSmartScribeCore
import SwiftUI

/// Shared layout metrics for the provider quick switcher. Kept in one place so
/// the SwiftUI list rendering and the AppKit mouse hit-testing agree exactly.
enum QuickSwitcherLayout {
    static let rowHeight: CGFloat = 24
    static let rowSpacing: CGFloat = 2
    static let verticalPadding: CGFloat = 6
    static let horizontalPadding: CGFloat = 10
    static let width: CGFloat = 190
    static let dividerHeight: CGFloat = 7

    static func hasDivider(providers: [ProviderQuickSwitcherModel.Provider]) -> Bool {
        providers.count > 1 && providers.first?.id == "mlx-swift-local-model"
    }

    static func contentHeight(providers: [ProviderQuickSwitcherModel.Provider]) -> CGFloat {
        let rowCount = providers.count
        guard rowCount > 0 else { return 0 }
        let base = verticalPadding * 2
            + CGFloat(rowCount) * rowHeight
            + CGFloat(max(0, rowCount - 1)) * rowSpacing
        return hasDivider(providers: providers) ? base + dividerHeight : base
    }

    /// Maps a point (in content-view coordinates, origin bottom-left) to a
    /// top-to-bottom row index, ignoring clicks that land in spacing gaps or the divider.
    static func rowIndex(forY y: CGFloat, providers: [ProviderQuickSwitcherModel.Provider]) -> Int? {
        let rowCount = providers.count
        guard rowCount > 0 else { return nil }
        let height = contentHeight(providers: providers)
        var fromTop = height - y - verticalPadding
        guard fromTop >= 0 else { return nil }

        let withDivider = hasDivider(providers: providers)

        // Row 0 (Local.AI)
        if fromTop <= rowHeight {
            return 0
        }

        if withDivider {
            if fromTop <= rowHeight + dividerHeight + rowSpacing {
                return nil // Landed inside the divider gap
            }
            fromTop -= dividerHeight
        }

        let stride = rowHeight + rowSpacing
        let index = Int(fromTop / stride)
        let withinRow = fromTop - CGFloat(index) * stride
        guard index >= 0, index < rowCount, withinRow <= rowHeight else { return nil }
        return index
    }
}

/// A selectable model entry shown in a provider's right-click model menu.
struct QuickSwitcherModelItem: Identifiable, Equatable {
    let id: String
    let displayName: String
}

/// Nonactivating, translucent panel that hosts the provider quick switcher.
/// Mirrors the hotkey HUD panel so it never steals focus from the dictation
/// target application.
final class ProviderQuickSwitcherPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar + 2
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Transparent frontmost view that captures hover/click/right-click/scroll over
/// the rendered provider list, mirroring `OverlayMouseCaptureView`.
final class ProviderQuickSwitcherCaptureView: NSView {
    var providers: [ProviderQuickSwitcherModel.Provider] = []
    var onLeftClickRow: ((_ index: Int) -> Void)?
    var onRightClickRow: ((_ index: Int, _ locationInWindow: NSPoint) -> Void)?
    var onScroll: ((_ deltaY: CGFloat) -> Void)?
    var onHoverChanged: ((_ hovering: Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    override func mouseUp(with event: NSEvent) {
        guard event.buttonNumber == 0 else {
            super.mouseUp(with: event)
            return
        }
        if let index = QuickSwitcherLayout.rowIndex(forY: event.locationInWindow.y, providers: providers) {
            onLeftClickRow?(index)
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        if let index = QuickSwitcherLayout.rowIndex(forY: event.locationInWindow.y, providers: providers) {
            onRightClickRow?(index, event.locationInWindow)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY
            : event.scrollingDeltaY * ProviderQuickSwitcherModel.defaultStepThreshold
        if abs(delta) > 0.001 {
            onScroll?(delta)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Observable state driving the rendered provider list.
@MainActor
final class ProviderQuickSwitcherListViewModel: ObservableObject {
    @Published var providers: [ProviderQuickSwitcherModel.Provider] = []
    @Published var activeID: String?
}

/// SwiftUI rendering of the provider list (names only, active row highlighted).
/// All interaction is handled by the AppKit capture view layered on top, so the
/// background stays clear and lets the panel's material show through.
struct ProviderQuickSwitcherListView: View {
    @ObservedObject var viewModel: ProviderQuickSwitcherListViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: QuickSwitcherLayout.rowSpacing) {
            ForEach(Array(viewModel.providers.enumerated()), id: \.element.id) { index, provider in
                row(for: provider)
                if index == 0 && QuickSwitcherLayout.hasDivider(providers: viewModel.providers) {
                    Divider()
                        .background(Color.white.opacity(0.18))
                        .padding(.vertical, 2)
                }
            }
        }
        .padding(.vertical, QuickSwitcherLayout.verticalPadding)
        .padding(.horizontal, QuickSwitcherLayout.horizontalPadding)
        .frame(width: QuickSwitcherLayout.width, alignment: .leading)
    }

    private func row(for provider: ProviderQuickSwitcherModel.Provider) -> some View {
        let isActive = provider.id == viewModel.activeID
        return HStack(spacing: 6) {
            Circle()
                .fill(isActive ? Color.green : Color.white.opacity(0.25))
                .frame(width: 6, height: 6)
            Text(provider.displayName)
                .font(
                    .system(
                        size: 12,
                        weight: isActive ? .semibold : .regular,
                        design: .rounded
                    )
                )
                .foregroundStyle(isActive ? .white : .white.opacity(0.78))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(height: QuickSwitcherLayout.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isActive ? Color.white.opacity(0.16) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

/// Owns the nonactivating provider quick-switcher panel: shows/updates/hides it
/// in response to HUD scroll events, live-switches providers, and forwards
/// right-clicks so the owner can present a per-provider model menu.
@MainActor
final class ProviderQuickSwitcher {
    typealias Provider = ProviderQuickSwitcherModel.Provider

    /// Called when the active provider should change (scroll or left click).
    var onSwitchProvider: ((String) -> Void)?
    /// Called on right-click of a row; the owner builds and pops the model menu
    /// synchronously. The panel stays visible while the menu is open.
    var onModelMenuRequested: ((_ providerID: String, _ anchorView: NSView, _ locationInAnchor: NSPoint) -> Void)?

    private let panel: ProviderQuickSwitcherPanel
    private let effectView: NSVisualEffectView
    private let hostingController: NSHostingController<ProviderQuickSwitcherListView>
    private let captureView = ProviderQuickSwitcherCaptureView()
    private let listViewModel = ProviderQuickSwitcherListViewModel()

    private var model: ProviderQuickSwitcherModel
    private var hideTimer: Timer?
    private var isHovering = false
    private let hideDelay: TimeInterval = 1.4

    init() {
        model = ProviderQuickSwitcherModel(providers: [], activeID: nil)
        let initialRect = NSRect(x: 0, y: 0, width: QuickSwitcherLayout.width, height: 1)
        panel = ProviderQuickSwitcherPanel(contentRect: initialRect)

        effectView = NSVisualEffectView(frame: initialRect)
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 10
        effectView.layer?.masksToBounds = true
        effectView.layer?.borderWidth = 1
        effectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor

        hostingController = NSHostingController(
            rootView: ProviderQuickSwitcherListView(viewModel: listViewModel)
        )

        panel.contentView = effectView
        let hosted = hostingController.view
        hosted.frame = effectView.bounds
        hosted.autoresizingMask = [.width, .height]
        effectView.addSubview(hosted)

        captureView.frame = effectView.bounds
        captureView.autoresizingMask = [.width, .height]
        effectView.addSubview(captureView)

        captureView.onLeftClickRow = { [weak self] index in
            self?.handleLeftClick(index: index)
        }
        captureView.onRightClickRow = { [weak self] index, location in
            self?.handleRightClick(index: index, locationInWindow: location)
        }
        captureView.onScroll = { [weak self] delta in
            self?.applyScroll(deltaY: delta)
        }
        captureView.onHoverChanged = { [weak self] hovering in
            self?.setHovering(hovering)
        }
    }

    var isVisible: Bool { panel.isVisible }

    /// Shows or updates the switcher anchored near the HUD frame.
    func show(providers: [Provider], activeID: String?, anchorFrame: NSRect) {
        guard !providers.isEmpty else {
            hide()
            return
        }
        if model.providers != providers {
            model = ProviderQuickSwitcherModel(
                providers: providers, activeID: activeID, now: currentTime())
        } else {
            model.setActive(id: activeID)
        }
        listViewModel.providers = providers
        listViewModel.activeID = model.activeProvider?.id ?? activeID
        captureView.providers = providers

        layoutAndPosition(anchorFrame: anchorFrame)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        scheduleHide()
    }

    func hide() {
        cancelHideTimer()
        isHovering = false
        panel.orderOut(nil)
    }

    /// Entry point for HUD scroll events: ensures the panel is visible and
    /// applies the scroll step.
    func handleHUDScroll(
        deltaY: CGFloat,
        providers: [Provider],
        activeID: String?,
        anchorFrame: NSRect
    ) {
        show(providers: providers, activeID: activeID, anchorFrame: anchorFrame)
        applyScroll(deltaY: deltaY)
    }

    private func applyScroll(deltaY: CGFloat) {
        if let selected = model.applyScroll(deltaY: deltaY, now: currentTime()) {
            listViewModel.activeID = selected.id
            onSwitchProvider?(selected.id)
        }
        scheduleHide()
    }

    private func handleLeftClick(index: Int) {
        guard model.providers.indices.contains(index) else { return }
        let provider = model.providers[index]
        model.select(id: provider.id)
        listViewModel.activeID = provider.id
        onSwitchProvider?(provider.id)
        scheduleHide()
    }

    private func handleRightClick(index: Int, locationInWindow: NSPoint) {
        guard model.providers.indices.contains(index) else { return }
        let provider = model.providers[index]
        // Keep the list visible while the (synchronous) model menu is open.
        cancelHideTimer()
        onModelMenuRequested?(provider.id, captureView, locationInWindow)
        scheduleHide()
    }

    private func setHovering(_ hovering: Bool) {
        isHovering = hovering
        if hovering {
            cancelHideTimer()
        } else {
            scheduleHide()
        }
    }

    private func scheduleHide() {
        cancelHideTimer()
        guard !isHovering else { return }
        let timer = Timer(timeInterval: hideDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.hideIfNotHovering()
            }
        }
        // `.default` mode pauses the timer during modal menu tracking, so the
        // panel stays put while a model menu is open.
        RunLoop.main.add(timer, forMode: .default)
        hideTimer = timer
    }

    private func hideIfNotHovering() {
        guard !isHovering else { return }
        hide()
    }

    private func cancelHideTimer() {
        hideTimer?.invalidate()
        hideTimer = nil
    }

    private func layoutAndPosition(anchorFrame: NSRect) {
        let height = QuickSwitcherLayout.contentHeight(providers: model.providers)
        let size = NSSize(width: QuickSwitcherLayout.width, height: height)

        var origin = NSPoint(
            x: anchorFrame.midX - size.width / 2,
            y: anchorFrame.minY - height - 8
        )
        if let screen = screenForFrame(anchorFrame) {
            let visible = screen.visibleFrame
            if origin.y < visible.minY {
                origin.y = anchorFrame.maxY + 8
            }
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
            if origin.y + height > visible.maxY {
                origin.y = visible.maxY - height - 4
            }
        }

        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        effectView.frame = NSRect(origin: .zero, size: size)
        hostingController.view.frame = NSRect(origin: .zero, size: size)
        captureView.frame = NSRect(origin: .zero, size: size)
    }

    private func screenForFrame(_ frame: NSRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main
    }

    private func currentTime() -> TimeInterval {
        Date().timeIntervalSinceReferenceDate
    }
}
