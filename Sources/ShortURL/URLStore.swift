import Foundation

struct URLMapping: Codable {
    let originalURL: String
    let createdAt: Date
    var clicks: Int = 0
}

final class URLStore: @unchecked Sendable {
    private var mappings: [String: URLMapping] = [:]
    private let fileURL: URL
    private let lock = NSLock()

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let dir = appSupport.appendingPathComponent("ShortURL", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("mappings.json")

        // Load existing mappings synchronously from disk
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: URLMapping].self, from: data) {
            mappings = decoded
            print("[URLStore] Loaded \(mappings.count) mappings")
        } else {
            print("[URLStore] No existing mappings")
        }
    }

    private func saveUnlocked() {
        guard let data = try? JSONEncoder().encode(mappings) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func lookup(code: String) -> URLMapping? {
        lock.lock()
        defer { lock.unlock() }

        guard var mapping = mappings[code] else { return nil }
        mapping.clicks += 1
        mappings[code] = mapping
        saveUnlocked()
        return mapping
    }

    func save(code: String, originalURL: String) {
        lock.lock()
        defer { lock.unlock() }

        let mapping = URLMapping(originalURL: originalURL, createdAt: Date())
        mappings[code] = mapping
        saveUnlocked()
        print("[URLStore] Saved: \(code) -> \(originalURL)")
    }
}
