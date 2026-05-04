import AppKit
import SwiftUI

@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    private let viewModel: NotchBroViewModel
    private let windowHorizontalPadding: CGFloat = 120
    private let windowVerticalPadding: CGFloat = 12
    private var window: NSWindow?
    private var pendingHideWorkItem: DispatchWorkItem?
    private var isApplyingProgrammaticResize = false

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
        containerView.isOpenResizeEnabled = { [weak self] in
            self?.viewModel.panelVisible ?? false
        }
        containerView.openShellRectProvider = { [weak self, weak containerView] in
            guard let self, let containerView else { return .zero }
            return self.openShellRect(in: containerView.bounds)
        }
        containerView.onOpenResize = { [weak self] edges, startFrame, startScreenLocation, currentScreenLocation in
            self?.resizeOpenPanel(
                using: edges,
                startFrame: startFrame,
                startScreenLocation: startScreenLocation,
                currentScreenLocation: currentScreenLocation
            )
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
        guard let window else { return }
        let frame = windowFrame()
        window.level = .statusBar
        isApplyingProgrammaticResize = true
        window.setFrame(frame, display: true, animate: animated)
        isApplyingProgrammaticResize = false
        syncWindowFocus(requestFocus: requestFocus)
        syncWindowVisibilityAfterInteraction(requestFocus: requestFocus)
        (window.contentView as? NotchContainerView)?.refreshClosedInteraction()
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

    private func openShellRect(in bounds: NSRect) -> NSRect {
        NSRect(
            x: bounds.midX - (viewModel.windowWidth / 2),
            y: bounds.maxY - viewModel.windowHeight,
            width: viewModel.windowWidth,
            height: viewModel.windowHeight
        )
    }

    private func windowFrame() -> NSRect {
        let screen = activeScreen()
        let screenFrame = screen?.frame ?? .zero
        let frameSize = openFrameSize()

        return NSRect(
            x: screenFrame.midX - (frameSize.width / 2),
            y: screenFrame.maxY - frameSize.height,
            width: frameSize.width,
            height: frameSize.height
        )
    }

    private func openPanelSize(from frameSize: NSSize) -> CGSize {
        CGSize(
            width: max(0, frameSize.width - windowHorizontalPadding),
            height: max(0, frameSize.height - windowVerticalPadding - viewModel.terminalChromeHeight)
        )
    }

    private func frameSize(width: CGFloat, viewportHeight: CGFloat) -> NSSize {
        NSSize(
            width: width + windowHorizontalPadding,
            height: viewportHeight + viewModel.terminalChromeHeight + windowVerticalPadding
        )
    }

    private func applyOpenPanelFrame(width: CGFloat, viewportHeight: CGFloat) {
        guard let window else { return }
        let clampedWidth = width.clamped(to: viewModel.effectiveOpenPanelWidthRange)
        let clampedViewportHeight = viewportHeight.clamped(to: viewModel.effectiveOpenPanelViewportHeightRange)
        viewModel.updateOpenPanelSize(width: clampedWidth, viewportHeight: clampedViewportHeight)
        let frameSize = frameSize(width: clampedWidth, viewportHeight: clampedViewportHeight)
        let screenMidX = activeScreen()?.frame.midX ?? window.frame.midX
        let updatedFrame = NSRect(
            x: screenMidX - (frameSize.width / 2),
            y: window.frame.maxY - frameSize.height,
            width: frameSize.width,
            height: frameSize.height
        )
        isApplyingProgrammaticResize = true
        window.setFrame(updatedFrame, display: true)
        isApplyingProgrammaticResize = false
    }

    private func resizeOpenPanel(
        using edges: OpenResizeProxyView.ResizeEdges,
        startFrame: NSRect,
        startScreenLocation: NSPoint,
        currentScreenLocation: NSPoint
    ) {
        guard viewModel.panelVisible, !isApplyingProgrammaticResize else { return }

        let deltaX = currentScreenLocation.x - startScreenLocation.x
        let deltaY = currentScreenLocation.y - startScreenLocation.y
        let initialOpenSize = openPanelSize(from: startFrame.size)

        var targetWidth = initialOpenSize.width
        var targetViewportHeight = initialOpenSize.height

        if edges.contains(.left) || edges.contains(.right) {
            let horizontalDelta = edges.contains(.left) ? -deltaX : deltaX
            targetWidth += horizontalDelta * 2
        }

        if edges.contains(.bottom) {
            targetViewportHeight -= deltaY
        }

        applyOpenPanelFrame(width: targetWidth, viewportHeight: targetViewportHeight)
    }

    private func activeScreen() -> NSScreen? {
        window?.screen ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func openFrameSize() -> NSSize {
        frameSize(width: viewModel.terminalWidth, viewportHeight: viewModel.terminalViewportMaxHeight)
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
                addSubview(hostingView, positioned: .below, relativeTo: openResizeProxyView)
            }
            installOpenResizeProxyIfNeeded()
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
    var isOpenResizeEnabled: (() -> Bool)? {
        didSet { openResizeProxyView.isResizeEnabled = isOpenResizeEnabled }
    }
    var openShellRectProvider: (() -> NSRect)? {
        didSet { openResizeProxyView.shellRectProvider = openShellRectProvider }
    }
    var onOpenResize: ((OpenResizeProxyView.ResizeEdges, NSRect, NSPoint, NSPoint) -> Void)? {
        didSet { openResizeProxyView.onResize = onOpenResize }
    }

    private var trackingAreaReference: NSTrackingArea?
    private var isHoveringClosedActivation = false
    private let closedDropProxyView = ClosedDropProxyView(frame: .zero)
    private let openResizeProxyView = OpenResizeProxyView(frame: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installOpenResizeProxyIfNeeded()
        installClosedDropProxyIfNeeded()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installOpenResizeProxyIfNeeded()
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
        openResizeProxyView.frame = bounds
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

    private func installOpenResizeProxyIfNeeded() {
        guard openResizeProxyView.superview !== self else { return }
        openResizeProxyView.frame = bounds
        openResizeProxyView.autoresizingMask = [.width, .height]
        addSubview(openResizeProxyView)
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

final class OpenResizeProxyView: NSView {
    struct ResizeEdges: OptionSet {
        let rawValue: Int

        static let left = ResizeEdges(rawValue: 1 << 0)
        static let right = ResizeEdges(rawValue: 1 << 1)
        static let bottom = ResizeEdges(rawValue: 1 << 2)
    }

    var isResizeEnabled: (() -> Bool)?
    var shellRectProvider: (() -> NSRect)?
    var onResize: ((ResizeEdges, NSRect, NSPoint, NSPoint) -> Void)?

    private let edgeThickness: CGFloat = 22
    private let cornerSize: CGFloat = 28
    private let edgeOutset: CGFloat = 10

    override func resetCursorRects() {
        discardCursorRects()
        guard isResizeEnabled?() == true else { return }

        let shellRect = shellRectProvider?() ?? .zero
        for (rect, cursor) in resizeCursorRects(around: shellRect) {
            addCursorRect(rect, cursor: cursor)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }

    override func layout() {
        super.layout()
        window?.invalidateCursorRects(for: self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isResizeEnabled?() == true else { return nil }
        return resizeEdges(at: point).isEmpty ? nil : self
    }

    override func mouseDown(with event: NSEvent) {
        guard isResizeEnabled?() == true, let window else {
            super.mouseDown(with: event)
            return
        }

        let localPoint = convert(event.locationInWindow, from: nil)
        let edges = resizeEdges(at: localPoint)
        guard !edges.isEmpty else {
            super.mouseDown(with: event)
            return
        }

        let startFrame = window.frame
        let startScreenLocation = NSEvent.mouseLocation

        while let nextEvent = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            switch nextEvent.type {
            case .leftMouseDragged:
                onResize?(edges, startFrame, startScreenLocation, NSEvent.mouseLocation)
            case .leftMouseUp:
                onResize?(edges, startFrame, startScreenLocation, NSEvent.mouseLocation)
                return
            default:
                break
            }
        }
    }

    private func resizeEdges(at point: NSPoint) -> ResizeEdges {
        let shellRect = shellRectProvider?() ?? .zero
        guard shellRect.width > 0, shellRect.height > 0 else { return [] }

        let bottomLeftCorner = NSRect(
            x: shellRect.minX - edgeOutset,
            y: shellRect.minY - edgeOutset,
            width: cornerSize + edgeOutset,
            height: cornerSize + edgeOutset
        )
        let bottomRightCorner = NSRect(
            x: shellRect.maxX - cornerSize,
            y: shellRect.minY - edgeOutset,
            width: cornerSize + edgeOutset,
            height: cornerSize + edgeOutset
        )
        var edges: ResizeEdges = []
        if bottomLeftCorner.contains(point) {
            return [.left, .bottom]
        }
        if bottomRightCorner.contains(point) {
            return [.right, .bottom]
        }

        let leftBand = NSRect(
            x: shellRect.minX - edgeOutset,
            y: shellRect.minY,
            width: edgeThickness + edgeOutset,
            height: shellRect.height
        )
        let rightBand = NSRect(
            x: shellRect.maxX - edgeThickness,
            y: shellRect.minY,
            width: edgeThickness + edgeOutset,
            height: shellRect.height
        )
        let bottomBand = NSRect(
            x: shellRect.minX,
            y: shellRect.minY - edgeOutset,
            width: shellRect.width,
            height: edgeThickness + edgeOutset
        )

        if leftBand.contains(point) {
            edges.insert(.left)
        } else if rightBand.contains(point) {
            edges.insert(.right)
        }

        if bottomBand.contains(point) {
            edges.insert(.bottom)
        }

        return edges
    }

    private func resizeCursorRects(around shellRect: NSRect) -> [(NSRect, NSCursor)] {
        guard shellRect.width > 0, shellRect.height > 0 else { return [] }

        let leftRect = NSRect(
            x: shellRect.minX - edgeOutset,
            y: shellRect.minY + cornerSize,
            width: edgeThickness + edgeOutset,
            height: max(0, shellRect.height - cornerSize)
        )
        let rightRect = NSRect(
            x: shellRect.maxX - edgeThickness,
            y: shellRect.minY + cornerSize,
            width: edgeThickness + edgeOutset,
            height: max(0, shellRect.height - cornerSize)
        )
        let bottomRect = NSRect(
            x: shellRect.minX + cornerSize,
            y: shellRect.minY - edgeOutset,
            width: max(0, shellRect.width - (cornerSize * 2)),
            height: edgeThickness + edgeOutset
        )
        let bottomLeftRect = NSRect(
            x: shellRect.minX - edgeOutset,
            y: shellRect.minY - edgeOutset,
            width: cornerSize + edgeOutset,
            height: cornerSize + edgeOutset
        )
        let bottomRightRect = NSRect(
            x: shellRect.maxX - cornerSize,
            y: shellRect.minY - edgeOutset,
            width: cornerSize + edgeOutset,
            height: cornerSize + edgeOutset
        )

        return [
            (leftRect, .resizeLeftRight),
            (rightRect, .resizeLeftRight),
            (bottomRect, .resizeUpDown),
            (bottomLeftRect, .closedHand),
            (bottomRightRect, .closedHand)
        ]
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

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
