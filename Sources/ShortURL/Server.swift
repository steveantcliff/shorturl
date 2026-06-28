import Foundation

/// Minimal HTTP server that redirects short codes to original URLs.
final class RedirectServer {
    private var listeningSocket: Int32 = -1
    private var dispatchSource: DispatchSourceRead?
    private var isRunning = false
    private(set) var port: UInt16 = 8080

    deinit { stop() }

    func start(port: UInt16, store: URLStore) async throws {
        self.port = port
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try startSync(port: port, store: store)
                continuation.resume()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func startSync(port: UInt16, store: URLStore) throws {
        var hints = addrinfo()
        hints.ai_flags = AI_PASSIVE | AI_ADDRCONFIG
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = 0

        var info: UnsafeMutablePointer<addrinfo>?
        let portString = "\(port)"
        let result = portString.withCString { ptr in
            getaddrinfo(nil, ptr, &hints, &info)
        }

        guard result == 0, let addr = info else {
            throw ServerError.bindFailed(String(cString: gai_strerror(result)))
        }
        defer { freeaddrinfo(info) }

        let sock = socket(addr.pointee.ai_family, addr.pointee.ai_socktype, addr.pointee.ai_protocol)
        guard sock >= 0 else {
            throw ServerError.socketFailed(String(cString: strerror(errno)))
        }

        // SO_REUSEADDR to avoid "address in use" after restart
        var reuse: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        // bind
        guard bind(sock, addr.pointee.ai_addr, addr.pointee.ai_addrlen) == 0 else {
            close(sock)
            throw ServerError.bindFailed(String(cString: strerror(errno)))
        }

        // listen
        guard listen(sock, 128) == 0 else {
            close(sock)
            throw ServerError.listenFailed(String(cString: strerror(errno)))
        }

        // Non-blocking
        let flags = fcntl(sock, F_GETFL, 0)
        _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

        listeningSocket = sock
        isRunning = true

        let source = DispatchSource.makeReadSource(fileDescriptor: sock, queue: .global(qos: .default))
        source.setEventHandler { [weak self] in
            self?.acceptConnections(store: store)
        }
        source.setCancelHandler { [weak self] in
            if let sock = self?.listeningSocket, sock >= 0 {
                close(sock)
            }
        }
        source.resume()
        dispatchSource = source

        print("[Server] Listening on port \(port)")
    }

    func stop() {
        isRunning = false
        dispatchSource?.cancel()
        dispatchSource = nil
        if listeningSocket >= 0 {
            close(listeningSocket)
            listeningSocket = -1
        }
        print("[Server] Stopped")
    }

    private func acceptConnections(store: URLStore) {
        var clientAddr = sockaddr()
        var clientLen = socklen_t(MemoryLayout<sockaddr>.size)

        let client = accept(listeningSocket, &clientAddr, &clientLen)
        guard client >= 0 else { return }

        DispatchQueue.global(qos: .default).async { [weak self] in
            self?.handleConnection(client, store: store)
        }
    }

    private func handleConnection(_ client: Int32, store: URLStore) {
        // Read request with timeout
        var pollFd = pollfd(fd: client, events: Int16(POLLIN), revents: 0)
        let pollResult = poll(&pollFd, 1, 5000) // 5s timeout

        guard pollResult > 0, (pollFd.revents & Int16(POLLIN)) != 0 else {
            close(client)
            return
        }

        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = recv(client, &buffer, buffer.count, 0)
        guard bytesRead > 0 else {
            close(client)
            return
        }

        let requestData = Data(buffer[0..<bytesRead])
        guard let requestLine = parseRequestLine(requestData) else {
            sendResponse(client, status: 400, body: "Bad Request")
            close(client)
            return
        }

        let path = requestLine.path
        print("[Server] GET \(path)")

        // Route: root page — respond synchronously
        if path == "/" {
            sendRootPage(client)
            close(client)
            return
        }

        // Strip leading slash
        let code = String(path.dropFirst())

        // Validate code format: 8 alphanumeric characters
        guard code.count == 8, code.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            sendResponse(client, status: 404, body: notFoundHTML(code: path))
            close(client)
            return
        }

        // Lookup in store — keep socket alive until async response is sent
        Task {
            if let mapping = await store.lookup(code: code) {
                sendRedirect(client, to: mapping.originalURL)
            } else {
                sendResponse(client, status: 404, body: notFoundHTML(code: code))
            }
            close(client)
        }
    }

    // MARK: - Request parsing

    private struct RequestLine {
        let method: String
        let path: String
    }

    private func parseRequestLine(_ data: Data) -> RequestLine? {
        guard let str = String(data: data, encoding: .utf8) else { return nil }
        let lines = str.components(separatedBy: "\r\n")
        guard let first = lines.first else { return nil }
        let parts = first.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }
        return RequestLine(method: parts[0].uppercased(), path: parts[1])
    }

    // MARK: - Response helpers

    private func sendResponse(_ socket: Int32, status: Int, body: String, contentType: String = "text/html; charset=utf-8") {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 302: statusText = "Found"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        default: statusText = "Unknown"
        }

        let response = """
        HTTP/1.1 \(status) \(statusText)\r
        Server: short.url\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """

        guard let data = response.data(using: .utf8) else { return }
        _ = data.withUnsafeBytes { ptr in
            send(socket, ptr.baseAddress, data.count, 0)
        }
    }

    private func sendRedirect(_ socket: Int32, to url: String) {
        let body = """
        <!DOCTYPE html>
        <html><head><meta http-equiv="refresh" content="0;url=\(url)">
        <script>location.href="\(url)"</script></head>
        <body>Redirecting to <a href="\(url)">\(url)</a></body></html>
        """

        let response = """
        HTTP/1.1 302 Found\r
        Server: short.url\r
        Location: \(url)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """

        guard let data = response.data(using: .utf8) else { return }
        _ = data.withUnsafeBytes { ptr in
            send(socket, ptr.baseAddress, data.count, 0)
        }
    }

    private func sendRootPage(_ socket: Int32) {
        let body = """
        <!DOCTYPE html>
        <html lang="en">
        <head><meta charset="utf-8"><title>short.url</title>
        <style>
          body { font-family: -apple-system, sans-serif; display: flex; justify-content: center;
                 align-items: center; min-height: 100vh; margin: 0; background: #f5f5f7; color: #1d1d1f; }
          .card { background: white; border-radius: 16px; padding: 40px; text-align: center;
                  box-shadow: 0 4px 24px rgba(0,0,0,0.08); max-width: 400px; }
          h1 { font-size: 24px; margin: 0 0 8px; }
          p { color: #86868b; margin: 0 0 24px; font-size: 14px; }
          code { background: #f5f5f7; padding: 4px 10px; border-radius: 6px; font-size: 13px; }
        </style></head>
        <body>
        <div class="card">
          <h1>🔗 short.url</h1>
          <p>Local URL shortening service is running.</p>
          <p><code>short.url:\(port)/XXXXXXXX</code></p>
        </div></body></html>
        """

        sendResponse(socket, status: 200, body: body)
    }

    private func notFoundHTML(code: String) -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head><meta charset="utf-8"><title>Not Found — short.url</title>
        <style>
          body { font-family: -apple-system, sans-serif; display: flex; justify-content: center;
                 align-items: center; min-height: 100vh; margin: 0; background: #f5f5f7; color: #1d1d1f; }
          .card { background: white; border-radius: 16px; padding: 40px; text-align: center;
                  box-shadow: 0 4px 24px rgba(0,0,0,0.08); max-width: 400px; }
          h1 { font-size: 20px; margin: 0 0 8px; }
          p { color: #86868b; margin: 0; font-size: 14px; }
          code { background: #f5f5f7; padding: 4px 10px; border-radius: 6px; font-size: 13px; }
        </style></head>
        <body>
        <div class="card">
          <h1>🔗 Not Found</h1>
          <p>No short URL matches <code>\(code)</code></p>
        </div></body></html>
        """
    }
}

// MARK: - Errors

enum ServerError: LocalizedError {
    case bindFailed(String)
    case socketFailed(String)
    case listenFailed(String)

    var errorDescription: String? {
        switch self {
        case .bindFailed(let msg): return "Bind failed: \(msg)"
        case .socketFailed(let msg): return "Socket failed: \(msg)"
        case .listenFailed(let msg): return "Listen failed: \(msg)"
        }
    }
}
