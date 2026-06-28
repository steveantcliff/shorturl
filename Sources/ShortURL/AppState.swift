import SwiftUI
import AppKit

// MARK: - App State

@MainActor
final class AppState: ObservableObject {
    @Published var inputURL: String = ""
    @Published var shortenedURL: String = ""
    @Published var copyButtonLabel: String = "Copy"
    @Published var serverRunning: Bool = false
    @Published var serverPort: UInt16 = 80
    @Published var statusMessage: String = ""
    @Published var statusIsError: Bool = false

    let store = URLStore()
    let server = RedirectServer()

    nonisolated init() {}

    func startServer() {
        Task {
            do {
                try await server.start(port: serverPort, store: store)
                await MainActor.run {
                    serverRunning = true
                    let portNote = serverPort == 80 ? "" : " (port \(serverPort))"
                    statusMessage = "Server running\(portNote)"
                    statusIsError = false
                }
            } catch {
                await MainActor.run {
                    serverRunning = false
                    if serverPort == 80 {
                        statusMessage = "Port 80 needs privileges. Run with sudo or change port."
                    } else {
                        statusMessage = "Server failed: \(error.localizedDescription)"
                    }
                    statusIsError = true
                }
            }
        }
    }

    func stopServer() {
        server.stop()
        serverRunning = false
        statusMessage = "Server stopped"
        statusIsError = false
    }

    func convertURL() {
        let trimmed = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "Please enter a URL"
            statusIsError = true
            return
        }

        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              !(url.host ?? "").isEmpty else {
            statusMessage = "Invalid URL — must start with http:// or https://"
            statusIsError = true
            return
        }

        let code = ShortCodeGenerator.generate()
        let normalizedURL = url.absoluteString

        Task {
            store.save(code: code, originalURL: normalizedURL)
            let shortURL = "http://short.url/\(code)"
            await MainActor.run {
                shortenedURL = shortURL
                copyButtonLabel = "Copy"
                statusMessage = "Shortened!"
                statusIsError = false
            }
        }
    }

    func copyToClipboard() {
        guard !shortenedURL.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(shortenedURL, forType: .string)
        copyButtonLabel = "Copied!"
        statusMessage = "Copied to clipboard"

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                if copyButtonLabel == "Copied!" {
                    copyButtonLabel = "Copy"
                }
            }
        }
    }
}
