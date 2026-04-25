import AppKit
import Foundation

enum FileDropPasteboardReader {
    static let registeredTypes: [NSPasteboard.PasteboardType] = [.fileURL]

    static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]

        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL] ?? []

        return urls.filter(\.isFileURL)
    }
}

enum DroppedPathFormatter {
    static func text(for urls: [URL], shellPath: String) -> String {
        let style = quotingStyle(for: shellPath)

        return urls
            .filter(\.isFileURL)
            .map(\.path)
            .map { quote($0, style: style) }
            .joined(separator: " ")
    }

    private enum QuotingStyle {
        case posixSingleQuoted
        case nushellDoubleQuoted
    }

    private static func quotingStyle(for shellPath: String) -> QuotingStyle {
        let shellName = URL(fileURLWithPath: shellPath).lastPathComponent.lowercased()

        switch shellName {
        case "nu", "nushell":
            return .nushellDoubleQuoted
        default:
            return .posixSingleQuoted
        }
    }

    private static func quote(_ path: String, style: QuotingStyle) -> String {
        switch style {
        case .posixSingleQuoted:
            let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
            return "'\(escaped)'"
        case .nushellDoubleQuoted:
            let escaped = path.replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
    }
}
