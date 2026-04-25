import AppKit
import Foundation
import SwiftTerm

@MainActor
protocol TerminalSessionControllerDelegate: AnyObject {
    func terminalSessionDidExit(_ controller: TerminalSessionController, exitCode: Int32?)
}

@MainActor
final class TerminalSessionController: NSObject, LocalProcessTerminalViewDelegate {
    let shellPath: String
    let workingDirectory: String
    let terminalView: BrodexTerminalView

    weak var delegate: TerminalSessionControllerDelegate?

    private(set) var sessionRunning = false
    private(set) var sessionExitCode: Int32?

    init(shellPath: String, workingDirectory: String, autostart: Bool = true) {
        self.shellPath = shellPath
        self.workingDirectory = workingDirectory
        let terminalView = BrodexTerminalView(frame: .zero)
        self.terminalView = terminalView
        super.init()
        configureTerminalView()
        if autostart {
            startShell()
        }
    }

    func focus() {
        guard let window = terminalView.window else { return }
        window.makeFirstResponder(terminalView)
    }

    private func configureTerminalView() {
        terminalView.processDelegate = self
        terminalView.autoresizingMask = [.width, .height]
        terminalView.configureNativeColors()
        terminalView.nativeForegroundColor = .white
        terminalView.nativeBackgroundColor = NSColor(
            calibratedRed: 0.02,
            green: 0.02,
            blue: 0.025,
            alpha: 1.0
        )
        terminalView.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        terminalView.optionAsMetaKey = true
        terminalView.caretViewTracksFocus = true
        styleTerminalScroller(in: terminalView)
    }

    private func startShell() {
        terminalView.startProcess(
            executable: shellPath,
            args: shellLaunchArguments(for: shellPath),
            environment: environmentArray(),
            currentDirectory: workingDirectory
        )
        sessionRunning = true
        sessionExitCode = nil
    }

    func insertDroppedFileURLs(_ urls: [URL]) {
        let insertedText = DroppedPathFormatter.text(for: urls, shellPath: shellPath)
        guard !insertedText.isEmpty else { return }
        terminalView.insertTextAtCursor(insertedText)
    }

    private func environmentArray() -> [String] {
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"

        return environment
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
    }

    private func shellLaunchArguments(for shellPath: String) -> [String] {
        let shellName = URL(fileURLWithPath: shellPath).lastPathComponent.lowercased()

        switch shellName {
        case "fish":
            return ["-i", "-l"]
        case "nu", "nushell":
            return []
        default:
            return ["-il"]
        }
    }

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
    }

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
    }

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            sessionRunning = false
            sessionExitCode = exitCode
            delegate?.terminalSessionDidExit(self, exitCode: exitCode)
        }
    }

    private func styleTerminalScroller(in view: NSView) {
        for subview in view.subviews {
            if let scroller = subview as? NSScroller {
                scroller.scrollerStyle = .overlay
                scroller.controlSize = .small
                scroller.alphaValue = 0.45
            } else {
                styleTerminalScroller(in: subview)
            }
        }
    }
}

/// SwiftTerm renders OSC 9;4 progress reports as an overlay bar above the
/// terminal content. Codex emits those reports, but in the notch UI the bar can
/// overlap the prompt row and look like a rendering glitch, so we ignore them.
final class BrodexTerminalView: LocalProcessTerminalView {
    private var oscBuffer: [UInt8] = []

    func insertTextAtCursor(_ text: String) {
        insertText(text, replacementRange: NSRange(location: 0, length: 0))
        scheduleFullRefreshIfVisible()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        scheduleFullRefreshIfVisible()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleFullRefreshIfVisible()
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        let filtered = stripProgressReports(from: Array(slice))
        guard !filtered.isEmpty else { return }
        super.dataReceived(slice: ArraySlice(filtered))
        scheduleFullRefreshIfVisible()
    }

    private func stripProgressReports(from bytes: [UInt8]) -> [UInt8] {
        oscBuffer.append(contentsOf: bytes)

        var output: [UInt8] = []
        var index = 0

        while index < oscBuffer.count {
            if oscBuffer[index] == 0x1B,
               index + 4 < oscBuffer.count,
               oscBuffer[index + 1] == 0x5D,
               oscBuffer[index + 2] == 0x39,
               oscBuffer[index + 3] == 0x3B,
               oscBuffer[index + 4] == 0x34 {
                if let terminator = progressReportTerminator(startingAt: index + 5) {
                    index = terminator
                    continue
                } else {
                    break
                }
            }

            output.append(oscBuffer[index])
            index += 1
        }

        if index > 0 {
            oscBuffer.removeFirst(index)
        }

        return output
    }

    private func progressReportTerminator(startingAt index: Int) -> Int? {
        var cursor = index
        while cursor < oscBuffer.count {
            let byte = oscBuffer[cursor]
            if byte == 0x07 {
                return cursor + 1
            }
            if byte == 0x1B, cursor + 1 < oscBuffer.count, oscBuffer[cursor + 1] == 0x5C {
                return cursor + 2
            }
            cursor += 1
        }
        return nil
    }

    private func scheduleFullRefreshIfVisible() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshVisibleSurface()
        }
    }

    private func refreshVisibleSurface() {
        guard superview != nil, window != nil else { return }
        terminal.updateFullScreen()
        needsDisplay = true
        setNeedsDisplay(bounds)
        displayIfNeeded()
    }
}
