import Foundation

enum ShortCodeGenerator {
    // Excludes ambiguous characters: 0 O o 1 I l
    private static let chars = Array("abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    private static let length = 8

    static func generate() -> String {
        var rng = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in chars[Int(rng.next() % UInt64(chars.count))] })
    }

    /// Generate a batch of unique codes
    static func generateBatch(count: Int) -> [String] {
        (0..<count).map { _ in generate() }
    }
}
