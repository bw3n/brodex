import Foundation
import Testing
@testable import BrodexV1Frontend

@MainActor
struct FileDropSupportTests {
    @Test
    func formatsPosixPathsWithSpacesAndMetacharacters() {
        let urls = [
            URL(fileURLWithPath: "/tmp/My File (Final).txt")
        ]

        #expect(
            DroppedPathFormatter.text(for: urls, shellPath: "/bin/zsh") ==
                "'/tmp/My File (Final).txt'"
        )
    }

    @Test
    func formatsSingleQuotesForPosixShells() {
        let urls = [
            URL(fileURLWithPath: "/tmp/that's wild.txt")
        ]

        #expect(
            DroppedPathFormatter.text(for: urls, shellPath: "/bin/bash") ==
                "'/tmp/that'\\''s wild.txt'"
        )
    }

    @Test
    func formatsMultiplePathsInDropOrder() {
        let urls = [
            URL(fileURLWithPath: "/tmp/alpha.txt"),
            URL(fileURLWithPath: "/tmp/Beta Folder")
        ]

        #expect(
            DroppedPathFormatter.text(for: urls, shellPath: "/bin/sh") ==
                "'/tmp/alpha.txt' '/tmp/Beta Folder'"
        )
    }

    @Test
    func formatsDirectoryPaths() {
        let urls = [
            URL(fileURLWithPath: "/tmp/Project Folder", isDirectory: true)
        ]

        #expect(
            DroppedPathFormatter.text(for: urls, shellPath: "/usr/bin/fish") ==
                "'/tmp/Project Folder'"
        )
    }

    @Test
    func fallsBackToPosixQuotingForUnknownShells() {
        let urls = [
            URL(fileURLWithPath: "/tmp/custom shell.txt")
        ]

        #expect(
            DroppedPathFormatter.text(for: urls, shellPath: "/opt/bin/customshell") ==
                "'/tmp/custom shell.txt'"
        )
    }

    @Test
    func formatsDoubleQuotesForNuShell() {
        let urls = [
            URL(fileURLWithPath: "/tmp/He said \"hi\".txt")
        ]

        #expect(
            DroppedPathFormatter.text(for: urls, shellPath: "/opt/homebrew/bin/nu") ==
                "\"/tmp/He said \\\"hi\\\".txt\""
        )
    }

    @Test
    func closedDropPreviewDoesNotOpenShell() {
        let viewModel = NotchBroViewModel(
            shellPath: "/bin/zsh",
            workingDirectory: "/tmp",
            startTerminalSession: false
        )

        viewModel.updateClosedDropInteraction(true)

        #expect(viewModel.shellState == .hidden)
        #expect(viewModel.dropInteractionState == .closedTarget)
        #expect(viewModel.closedDropPreviewVisible)
    }

    @Test
    func clearingDropPreviewResetsTransientState() {
        let viewModel = NotchBroViewModel(
            shellPath: "/bin/zsh",
            workingDirectory: "/tmp",
            startTerminalSession: false
        )

        viewModel.updateClosedDropInteraction(true)
        viewModel.clearDropInteraction()

        #expect(viewModel.dropInteractionState == .none)
        #expect(!viewModel.closedDropPreviewVisible)
    }

    @Test
    func acceptingDroppedFilesOpensShellAndClearsPreview() {
        let viewModel = NotchBroViewModel(
            shellPath: "/bin/zsh",
            workingDirectory: "/tmp",
            startTerminalSession: false
        )

        viewModel.updateClosedDropInteraction(true)
        viewModel.acceptDroppedFileURLs([URL(fileURLWithPath: "/tmp/example.txt")])

        #expect(viewModel.shellState == .open)
        #expect(viewModel.dropInteractionState == .none)
    }
}
