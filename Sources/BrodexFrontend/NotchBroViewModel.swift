import AppKit
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class NotchBroViewModel: TerminalSessionControllerDelegate {
    enum ShellState: Equatable {
        case hidden
        case hover
        case open
    }

    enum DropInteractionState: Equatable {
        case none
        case closedTarget
        case openTarget
    }

    private let shellAnimationResponse = 0.34
    private let shellAnimationDampingFraction = 0.84
    private let openPanelWidthDefault: CGFloat = 760
    private let openPanelViewportHeightDefault: CGFloat = 560
    private let openPanelWidthRange: ClosedRange<CGFloat> = 640...1_280
    private let openPanelViewportHeightRange: ClosedRange<CGFloat> = 360...820
    private let openPanelWidthKey = "NotchBro.openPanelWidth"
    private let openPanelViewportHeightKey = "NotchBro.openPanelViewportHeight"
    let shellPath: String
    let workingDirectory: String

    var shellState: ShellState = .hidden
    var dropInteractionState: DropInteractionState = .none
    let terminalSession: TerminalSessionController
    var sessionRunning = false
    var sessionExitCode: Int32?
    var openPanelWidth: CGFloat
    var openPanelViewportHeight: CGFloat

    init(shellPath: String? = nil, workingDirectory: String? = nil, startTerminalSession: Bool = true) {
        let environment = ProcessInfo.processInfo.environment
        let resolvedShell = shellPath?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? {
            let candidate = environment["SHELL"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return candidate.isEmpty ? "/bin/zsh" : candidate
        }()
        let fileManager = FileManager.default
        let launchDirectory = fileManager.currentDirectoryPath
        let cwd = workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? (
            launchDirectory.isEmpty || launchDirectory == "/"
            ? fileManager.homeDirectoryForCurrentUser.path
            : launchDirectory
        )

        self.shellPath = resolvedShell
        self.workingDirectory = cwd
        let defaults = UserDefaults.standard
        if defaults.object(forKey: openPanelWidthKey) != nil {
            openPanelWidth = defaults.double(forKey: openPanelWidthKey)
        } else {
            openPanelWidth = openPanelWidthDefault
        }
        if defaults.object(forKey: openPanelViewportHeightKey) != nil {
            openPanelViewportHeight = defaults.double(forKey: openPanelViewportHeightKey)
        } else {
            openPanelViewportHeight = openPanelViewportHeightDefault
        }
        terminalSession = TerminalSessionController(
            shellPath: resolvedShell,
            workingDirectory: cwd,
            autostart: startTerminalSession
        )
        terminalSession.delegate = self
        sessionRunning = terminalSession.sessionRunning
        sessionExitCode = terminalSession.sessionExitCode
        clampOpenPanelSize()
    }

    var panelVisible: Bool {
        shellState == .open
    }

    var hoverPreviewVisible: Bool {
        shellState == .hover && !closedDropPreviewVisible
    }

    var closedDropPreviewVisible: Bool {
        dropInteractionState == .closedTarget && !panelVisible
    }

    var openDropPreviewVisible: Bool {
        dropInteractionState == .openTarget && panelVisible
    }

    var dropInteractionActive: Bool {
        dropInteractionState != .none
    }

    var sessionStatusLabel: String {
        if sessionRunning {
            return "Running"
        }
        if let sessionExitCode {
            return "Exited (\(sessionExitCode))"
        }
        return "Stopped"
    }

    var shellTransitionAnimation: Animation {
        let scale = openPanelAnimationScale
        return .spring(
            response: shellAnimationResponse * scale,
            dampingFraction: min(0.92, shellAnimationDampingFraction + ((scale - 1) * 0.05))
        )
    }

    private var hardwareNotchSize: CGSize {
        NSScreen.builtin?.notchSize ?? NSScreen.main?.notchSize ?? CGSize(width: 184, height: 32)
    }

    var restingNotchWidth: CGFloat {
        hardwareNotchSize.width + 14

    }

    var restingNotchHeight: CGFloat {
        hardwareNotchSize.height
    }

    var hoverPreviewWidth: CGFloat {
        restingNotchWidth
    }

    var hoverPreviewHeight: CGFloat {
        restingNotchHeight
    }

    var terminalWidth: CGFloat {
        openPanelWidth
    }

    var closedDropPreviewWidth: CGFloat {
        420
    }

    var terminalViewportMaxHeight: CGFloat {
        openPanelViewportHeight
    }

    var closedDropPreviewHeight: CGFloat {
        214
    }

    var terminalChromeHeight: CGFloat {
        60
    }

    var terminalHeight: CGFloat {
        terminalViewportMaxHeight + terminalChromeHeight
    }

    var windowWidth: CGFloat {
        if closedDropPreviewVisible {
            return closedDropPreviewWidth
        }

        switch shellState {
        case .hidden:
            return restingNotchWidth
        case .hover:
            return hoverPreviewWidth
        case .open:
            return terminalWidth
        }
    }

    var windowHeight: CGFloat {
        if closedDropPreviewVisible {
            return closedDropPreviewHeight
        }

        switch shellState {
        case .hidden:
            return restingNotchHeight
        case .hover:
            return hoverPreviewHeight
        case .open:
            return terminalHeight
        }
    }

    var currentDirectoryName: String {
        let name = URL(fileURLWithPath: workingDirectory).lastPathComponent
        return name.isEmpty ? workingDirectory : name
    }

    func dismissPanel() {
        clearDropInteraction()
        setShellState(.hidden)
    }

    func openFromClosedState() {
        setShellState(.open)
    }

    func setHoveringNotch(_ hovering: Bool) {
        guard !panelVisible else { return }
        setShellState(hovering ? .hover : .hidden)
    }

    func updateClosedDropInteraction(_ active: Bool) {
        updateDropInteraction(.closedTarget, active: active)
    }

    func updateOpenDropInteraction(_ active: Bool) {
        updateDropInteraction(.openTarget, active: active)
    }

    func clearDropInteraction() {
        dropInteractionState = .none
    }

    func acceptDroppedFileURLs(_ urls: [URL]) {
        let fileURLs = urls.filter(\.isFileURL)
        clearDropInteraction()
        guard !fileURLs.isEmpty else { return }
        openFromClosedState()
        terminalSession.insertDroppedFileURLs(fileURLs)
    }

    func focusTerminal() {
        terminalSession.focus()
    }

    func updateOpenPanelSize(width: CGFloat, viewportHeight: CGFloat) {
        let clampedWidth = width.clamped(to: effectiveOpenPanelWidthRange)
        let clampedHeight = viewportHeight.clamped(to: effectiveOpenPanelViewportHeightRange)
        guard clampedWidth != openPanelWidth || clampedHeight != openPanelViewportHeight else { return }

        openPanelWidth = clampedWidth
        openPanelViewportHeight = clampedHeight

        let defaults = UserDefaults.standard
        defaults.set(Double(clampedWidth), forKey: openPanelWidthKey)
        defaults.set(Double(clampedHeight), forKey: openPanelViewportHeightKey)
    }

    var effectiveOpenPanelWidthRange: ClosedRange<CGFloat> {
        let minimum = max(openPanelWidthRange.lowerBound, closedDropPreviewWidth)
        let maximum = max(minimum, min(openPanelWidthRange.upperBound, maxUsableOpenPanelWidth))
        return minimum...maximum
    }

    var effectiveOpenPanelViewportHeightRange: ClosedRange<CGFloat> {
        let minimum = max(openPanelViewportHeightRange.lowerBound, 240)
        let maximum = max(minimum, min(openPanelViewportHeightRange.upperBound, maxUsableOpenPanelViewportHeight))
        return minimum...maximum
    }

    private var maxUsableOpenPanelWidth: CGFloat {
        let screen = NSScreen.main ?? NSScreen.builtin ?? NSScreen.screens.first
        let visibleWidth = screen?.visibleFrame.width ?? openPanelWidthRange.upperBound
        return max(openPanelWidthRange.lowerBound, visibleWidth - 120)
    }

    private var maxUsableOpenPanelViewportHeight: CGFloat {
        let screen = NSScreen.main ?? NSScreen.builtin ?? NSScreen.screens.first
        let visibleHeight = screen?.visibleFrame.height ?? openPanelViewportHeightRange.upperBound
        return max(openPanelViewportHeightRange.lowerBound, visibleHeight - terminalChromeHeight - 48)
    }

    private func clampOpenPanelSize() {
        updateOpenPanelSize(width: openPanelWidth, viewportHeight: openPanelViewportHeight)
    }

    private var openPanelAnimationScale: Double {
        let widthScale = openPanelWidth / openPanelWidthDefault
        let heightScale = openPanelViewportHeight / openPanelViewportHeightDefault
        let combinedScale = sqrt(Double(widthScale * heightScale))
        return min(max(combinedScale, 1.0), 1.3)
    }

    private func setShellState(_ newValue: ShellState) {
        guard shellState != newValue else { return }
        switch (shellState, newValue) {
        case (.hidden, .hover), (.hover, .hidden):
            withAnimation(shellTransitionAnimation) {
                shellState = newValue
            }
        default:
            // Avoid animating the live PTY resize. It causes terminal reflow
            // artifacts and feels laggy while the shell is active.
            shellState = newValue
        }
    }

    private func updateDropInteraction(_ target: DropInteractionState, active: Bool) {
        guard target != .none else { return }

        if active {
            guard dropInteractionState != target else { return }
            dropInteractionState = target
            return
        }

        if dropInteractionState == target {
            dropInteractionState = .none
        }
    }

    func terminalSessionDidExit(_ controller: TerminalSessionController, exitCode: Int32?) {
        sessionRunning = false
        sessionExitCode = exitCode
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension NSScreen {
    static var builtin: NSScreen? {
        if let builtin = screens.first(where: \.isBuiltinDisplay) {
            return builtin
        }
        return NSScreen.main
    }

    var isBuiltinDisplay: Bool {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return false
        }
        return CGDisplayIsBuiltin(screenNumber) != 0
    }

    var notchSize: CGSize {
        guard safeAreaInsets.top > 0 else {
            return CGSize(width: 184, height: 32)
        }

        let notchHeight = safeAreaInsets.top
        let leftPadding = auxiliaryTopLeftArea?.width ?? 0
        let rightPadding = auxiliaryTopRightArea?.width ?? 0

        guard leftPadding > 0, rightPadding > 0 else {
            return CGSize(width: 184, height: notchHeight)
        }

        let notchWidth = frame.width - leftPadding - rightPadding
        return CGSize(width: notchWidth, height: notchHeight)
    }
}
