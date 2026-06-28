import SwiftUI

struct ContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
                .padding(.top, 4)

            Divider()
                .padding(.horizontal, 16)
                .padding(.vertical, 4)

            // Main content
            VStack(alignment: .leading, spacing: 8) {
                // URL Input
                VStack(alignment: .leading, spacing: 4) {
                    Text("URL")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    TextField("https://example.com/very/long/url", text: $appState.inputURL)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                                )
                        )
                        .onSubmit {
                            appState.convertURL()
                        }
                }

                // Convert button
                Button(action: appState.convertURL) {
                    Label("Convert", systemImage: "arrow.triangle.branch")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(appState.inputURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                // Result
                if !appState.shortenedURL.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Shortened URL")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            Text(appState.shortenedURL)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(.blue)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            Button(action: appState.copyToClipboard) {
                                Label(appState.copyButtonLabel, systemImage: appState.copyButtonLabel == "Copied!" ? "checkmark.circle.fill" : "doc.on.doc")
                                    .labelStyle(.iconOnly)
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.borderless)
                            .help("Copy shortened URL to clipboard")
                        }
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.blue.opacity(0.06))
                        )
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)

            // Footer status
            footerView
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
        }
        .frame(width: 360, height: 216)
        .onAppear {
            appState.startServer()
        }
        .onDisappear {
            appState.stopServer()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 8) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.blue.gradient)
                .symbolRenderingMode(.hierarchical)

            Text("short.url")
                .font(.system(size: 16, weight: .bold, design: .rounded))

            Spacer()

            Circle()
                .fill(appState.serverRunning ? Color.green : Color.red)
                .frame(width: 7, height: 7)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack(spacing: 6) {
            if !appState.statusMessage.isEmpty {
                Image(systemName: appState.statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(appState.statusIsError ? .orange : .green)

                Text(appState.statusMessage)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if appState.serverPort != 443 {
                Text("port \(appState.serverPort)")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.6))
                    .monospacedDigit()
            }
        }
    }
}
