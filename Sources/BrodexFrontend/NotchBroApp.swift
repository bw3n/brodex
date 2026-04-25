import AppKit
import SwiftUI

@main
struct BrodexFrontend: App {
    @State private var viewModel = NotchBroViewModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(viewModel: viewModel)
        }
    }

    init() {
        AppDelegate.sharedViewModel = viewModel
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var sharedViewModel = NotchBroViewModel()
    private var windowCoordinator: WindowCoordinator?
    private var statusItemController: StatusItemController?
    private var viewModel: NotchBroViewModel { Self.sharedViewModel }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let coordinator = WindowCoordinator(viewModel: viewModel)
        coordinator.show()
        windowCoordinator = coordinator
        statusItemController = StatusItemController(
            openAction: { [weak self] in
                self?.windowCoordinator?.showPanel()
            },
            quitAction: {
                NSApplication.shared.terminate(nil)
            }
        )
    }
}

@MainActor
private final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let openAction: () -> Void
    private let quitAction: () -> Void

    init(openAction: @escaping () -> Void, quitAction: @escaping () -> Void) {
        self.openAction = openAction
        self.quitAction = quitAction
        super.init()
        configureStatusItem()
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = makeStatusImage()
            button.imagePosition = .imageOnly
            button.toolTip = "Brodex"
        }

        let menu = NSMenu()
        let openItem = NSMenuItem(title: "Open Brodex", action: #selector(openSelected), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Brodex", action: #selector(quitSelected), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func makeStatusImage() -> NSImage? {
        let size = NSSize(width: 30, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]
        let text = ">B_" as NSString
        text.draw(
            in: NSRect(x: 0, y: 1, width: size.width, height: size.height),
            withAttributes: attributes
        )

        image.isTemplate = true
        return image
    }

    @objc
    private func openSelected() {
        openAction()
    }

    @objc
    private func quitSelected() {
        quitAction()
    }
}

private struct SettingsView: View {
    @Bindable var viewModel: NotchBroViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Brodex V1")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Text("Brodex launches a persistent shell session that lives in the notch.")
                .foregroundStyle(.secondary)
            Divider()
            Text("Shell")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
            Text(viewModel.shellPath)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .textSelection(.enabled)
            Text("Working Directory")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
            Text(viewModel.workingDirectory)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .textSelection(.enabled)
            Text("Session State: \(viewModel.sessionStatusLabel)")
                .foregroundStyle(.secondary)
            Text("Hover the notch, click to open the terminal, and close it to hide the same session.")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
        .frame(width: 560, height: 280)
    }
}
