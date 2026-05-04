import AppKit
import SwiftUI

@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    private let viewModel: NotchBroViewModel
    private var window: NSWindow?
    private var pendingHideWorkItem: DispatchWorkItem?

    init(viewModel: NotchBroViewModel) {
        self.viewModel = viewModel
    }

    func show() {
        configureWindow()
        updateWindow(animated: false)
        window?.orderFrontRegardless()
    }

    func showPanel() {
        configureWindow()
        viewModel.openFromClosedState()
        updateWindow(animated: false, requestFocus: true)
    }

    private func configureWindow() {
        guard window == nil else { return }
        let frame = windowFrame()

        let panel = NotchPanel(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let rootView = ExpandedPanelView(viewModel: viewModel) { [weak self] in
            self?.viewModel.dismissPanel()
            self?.updateWindow(animated: false)
        } onLayoutChange: { [weak self] in
            self?.updateWindow(animated: false)
        }

        let hostingView = NSHostingView(rootView: AnyView(rootView))
        let containerView = NotchContainerView(frame: NSRect(origin: .zero, size: frame.size))
        containerView.hostingView = hostingView
        containerView.onClosedActivate = { [weak self] in
            self?.viewModel.openFromClosedState()
            self?.updateWindow(animated: false, requestFocus: true)
        }
        containerView.onClosedHoverChanged = { [weak self] hovering in
            self?.viewModel.setHoveringNotch(hovering)
            self?.updateWindow(animated: false)
        }
        containerView.onClosedDropTargetChanged = { [weak self] isTargeted in
            self?.viewModel.updateClosedDropInteraction(isTargeted)
            self?.updateWindow(animated: false)
        }
        containerView.onClosedFileDrop = { [weak self] urls in
            self?.viewModel.acceptDroppedFileURLs(urls)
            self?.updateWindow(animated: false, requestFocus: true)
        }
        containerView.isClosedInteractionEnabled = { [weak self] in
            !(self?.viewModel.panelVisible ?? true)
        }
        containerView.activationRectProvider = { [weak self, weak containerView] in
            guard let self, let containerView else { return .zero }
            return self.closedActivationRect(in: containerView.bounds)
        }
        containerView.dropPreviewRectProvider = { [weak self, weak containerView] in
            guard let self, let containerView else { return .zero }
            return self.closedDropPreviewRect(in: containerView.bounds)
        }
        containerView.isClosedDropPreviewVisible = { [weak self] in
            self?.viewModel.closedDropPreviewVisible ?? false
        }

        panel.contentView = containerView
        window = panel
    }

    private func scheduleHideAfterFocusLoss() {
        guard viewModel.panelVisible else { return }

        pendingHideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.viewModel.panelVisible else { return }
            guard self.viewModel.dropInteractionState == .none else { return }
            guard let window = self.window, !window.isKeyWindow else { return }
            self.viewModel.dismissPanel()
            self.updateWindow(animated: false)
        }
        pendingHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    private func cancelScheduledHide() {
        pendingHideWorkItem?.cancel()
        pendingHideWorkItem = nil
    }

    func windowDidBecomeKey(_ notification: Notification) {
        cancelScheduledHide()
    }

    func windowDidResignKey(_ notification: Notification) {
        scheduleHideAfterFocusLoss()
    }

    func windowDidResignMain(_ notification: Notification) {
        scheduleHideAfterFocusLoss()
    }

    deinit {
        MainActor.assumeIsolated {
            pendingHideWorkItem?.cancel()
        }
    }

    private func updateWindow(animated: Bool, requestFocus: Bool = false) {
        let frame = windowFrame()
        window?.level = .statusBar
        window?.setFrame(frame, display: true, animate: animated)
        syncWindowFocus(requestFocus: requestFocus)
        syncWindowVisibilityAfterInteraction(requestFocus: requestFocus)
        (window?.contentView as? NotchContainerView)?.refreshClosedInteraction()
    }

    private func syncWindowFocus(requestFocus: Bool) {
        guard let window else { return }
        if viewModel.panelVisible {
            if requestFocus {
                cancelScheduledHide()
                NSApplication.shared.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard self.viewModel.panelVisible else { return }
                    guard self.viewModel.dropInteractionState == .none else { return }
                    self.viewModel.focusTerminal()
                }
            } else {
                window.orderFrontRegardless()
            }
        } else {
            window.orderFrontRegardless()
        }
    }

    private func syncWindowVisibilityAfterInteraction(requestFocus: Bool) {
        guard let window else { return }

        if viewModel.dropInteractionActive {
            cancelScheduledHide()
            return
        }

        if viewModel.panelVisible, !window.isKeyWindow, !requestFocus {
            scheduleHideAfterFocusLoss()
        } else {
            cancelScheduledHide()
        }
    }

    private func closedActivationRect(in bounds: NSRect) -> NSRect {
        let activationWidth = max(viewModel.restingNotchWidth + 84, 260)
        let activationHeight = max(viewModel.restingNotchHeight + 26, 58)

        return NSRect(
            x: bounds.midX - (activationWidth / 2),
            y: bounds.maxY - activationHeight,
            width: activationWidth,
            height: activationHeight
        )
    }

    private func closedDropPreviewRect(in bounds: NSRect) -> NSRect {
        let previewWidth = viewModel.closedDropPreviewWidth
        let previewHeight = viewModel.closedDropPreviewHeight

        return NSRect(
            x: bounds.midX - (previewWidth / 2),
            y: bounds.maxY - previewHeight,
            width: previewWidth,
            height: previewHeight
        )
    }

    private func windowFrame() -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        let screenFrame = screen.frame
        let width = max(viewModel.terminalWidth + 120, viewModel.restingNotchWidth + 120, 320)
        let height = max(0, viewModel.terminalHeight + 12)

        return NSRect(
            x: screenFrame.midX - (width / 2),
            y: screenFrame.maxY - height,
            width: width,
            height: height
        )
    }
}

private final class NotchPanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           event.keyCode == 53,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
           let onEscape {
            onEscape()
            return
        }
        super.sendEvent(event)
    }
}

private final class NotchContainerView: NSView {
    var hostingView: NSHostingView<AnyView>? {
        didSet {
            oldValue?.removeFromSuperview()
            if let hostingView {
                hostingView.frame = bounds
                hostingView.autoresizingMask = [.width, .height]
                addSubview(hostingView, positioned: .below, relativeTo: closedDropProxyView)
            }
            installClosedDropProxyIfNeeded()
        }
    }

    var onClosedActivate: (() -> Void)?
    var onClosedHoverChanged: ((Bool) -> Void)?
    var onClosedDropTargetChanged: ((Bool) -> Void)? {
        didSet { closedDropProxyView.onClosedDropTargetChanged = onClosedDropTargetChanged }
    }
    var onClosedFileDrop: (([URL]) -> Void)? {
        didSet { closedDropProxyView.onClosedFileDrop = onClosedFileDrop }
    }
    var isClosedInteractionEnabled: (() -> Bool)? {
        didSet { closedDropProxyView.isClosedInteractionEnabled = isClosedInteractionEnabled }
    }
    var activationRectProvider: (() -> NSRect)? {
        didSet { closedDropProxyView.activationRectProvider = activationRectProvider }
    }
    var dropPreviewRectProvider: (() -> NSRect)? {
        didSet { closedDropProxyView.dropPreviewRectProvider = dropPreviewRectProvider }
    }
    var isClosedDropPreviewVisible: (() -> Bool)? {
        didSet { closedDropProxyView.isClosedDropPreviewVisible = isClosedDropPreviewVisible }
    }

    private var trackingAreaReference: NSTrackingArea?
    private var isHoveringClosedActivation = false
    private let closedDropProxyView = ClosedDropProxyView(frame: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installClosedDropProxyIfNeeded()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installClosedDropProxyIfNeeded()
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        true
    }

    override func layout() {
        super.layout()
        hostingView?.frame = bounds
        closedDropProxyView.frame = bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if isClosedInteractionEnabled?() == true,
           isPointInsideActivation(point) {
            return self
        }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if isClosedInteractionEnabled?() == true,
           isPointInsideActivation(location) {
            onClosedActivate?()
            return
        }
        super.mouseDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let isVerticalGesture = abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX)

        if isClosedInteractionEnabled?() == true,
           isVerticalGesture,
           isPointInsideActivation(location) {
            onClosedActivate?()
            return
        }

        super.scrollWheel(with: event)
    }

    override func updateTrackingAreas() {
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaReference = trackingArea
        refreshClosedInteraction()
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        updateClosedHover(with: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        updateClosedHover(with: convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateClosedHover(with: convert(event.locationInWindow, from: nil))
    }

    func refreshClosedInteraction() {
        guard let window else {
            setClosedHover(false)
            return
        }
        let location = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        updateClosedHover(with: location)
    }

    private func updateClosedHover(with point: NSPoint) {
        guard isClosedInteractionEnabled?() == true else {
            setClosedHover(false)
            return
        }

        setClosedHover(isPointInsideActivation(point))
    }

    private func setClosedHover(_ hovering: Bool) {
        guard hovering != isHoveringClosedActivation else { return }
        isHoveringClosedActivation = hovering
        onClosedHoverChanged?(hovering)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    private func installClosedDropProxyIfNeeded() {
        guard closedDropProxyView.superview !== self else { return }
        closedDropProxyView.frame = bounds
        closedDropProxyView.autoresizingMask = [.width, .height]
        addSubview(closedDropProxyView)
    }

    private func expandedActivationRect() -> NSRect {
        (activationRectProvider?() ?? .zero).insetBy(dx: -1, dy: -2)
    }

    private func isPointInsideActivation(_ point: NSPoint) -> Bool {
        let rect = expandedActivationRect()
        return point.x >= rect.minX &&
            point.x <= rect.maxX &&
            point.y >= rect.minY &&
            point.y <= rect.maxY + 1
    }
}

private final class ClosedDropProxyView: NSView {
    var onClosedDropTargetChanged: ((Bool) -> Void)?
    var onClosedFileDrop: (([URL]) -> Void)?
    var isClosedInteractionEnabled: (() -> Bool)?
    var activationRectProvider: (() -> NSRect)?
    var dropPreviewRectProvider: (() -> NSRect)?
    var isClosedDropPreviewVisible: (() -> Bool)?

    private var isClosedDropTargeted = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(FileDropPasteboardReader.registeredTypes)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes(FileDropPasteboardReader.registeredTypes)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateClosedDropState(with: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateClosedDropState(with: sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setClosedDropTargeted(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !FileDropPasteboardReader.fileURLs(from: sender.draggingPasteboard).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let location = convert(sender.draggingLocation, from: nil)
        let urls = FileDropPasteboardReader.fileURLs(from: sender.draggingPasteboard)
        let isInsideTarget = isPointInsideClosedDropTarget(location)
        setClosedDropTargeted(false)

        guard isClosedInteractionEnabled?() == true else { return false }
        guard isInsideTarget, !urls.isEmpty else { return false }
        onClosedFileDrop?(urls)
        return true
    }

    private func activeClosedDropRect() -> NSRect {
        let baseRect: NSRect
        if isClosedDropPreviewVisible?() == true {
            baseRect = dropPreviewRectProvider?() ?? .zero
        } else {
            baseRect = activationRectProvider?() ?? .zero
        }

        let expansion: CGFloat = (isClosedDropPreviewVisible?() == true) ? 16 : 28
        return baseRect.insetBy(dx: -expansion, dy: -16)
    }

    private func isPointInsideClosedDropTarget(_ point: NSPoint) -> Bool {
        let rect = activeClosedDropRect()
        return point.x >= rect.minX &&
            point.x <= rect.maxX &&
            point.y >= rect.minY &&
            point.y <= rect.maxY
    }

    private func updateClosedDropState(with draggingInfo: NSDraggingInfo) -> NSDragOperation {
        guard isClosedInteractionEnabled?() == true else {
            setClosedDropTargeted(false)
            return []
        }

        let urls = FileDropPasteboardReader.fileURLs(from: draggingInfo.draggingPasteboard)
        let location = convert(draggingInfo.draggingLocation, from: nil)
        let isInsideTarget = !urls.isEmpty && isPointInsideClosedDropTarget(location)

        setClosedDropTargeted(isInsideTarget)
        return isInsideTarget ? .copy : []
    }

    private func setClosedDropTargeted(_ targeted: Bool) {
        guard targeted != isClosedDropTargeted else { return }
        isClosedDropTargeted = targeted
        onClosedDropTargetChanged?(targeted)
    }
}
