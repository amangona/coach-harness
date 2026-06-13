import Foundation

/// Catalog of Google **Gemini TTS** prebuilt voices.
/// `id` is the `voiceName` passed to the TTS API and stored on `CoachPersona.voiceName`.
public struct GeminiVoice: Sendable, Identifiable, Hashable, Codable {
    public let id: String
    public let displayName: String
    public let descriptor: String
    public init(id: String, displayName: String, descriptor: String) {
        self.id = id
        self.displayName = displayName
        self.descriptor = descriptor
    }
}

public extension GeminiVoice {
    static let catalog: [GeminiVoice] = [
        .init(id: "Kore",   displayName: "Kore",   descriptor: "Warm, balanced"),
        .init(id: "Puck",   displayName: "Puck",   descriptor: "Upbeat, playful"),
        .init(id: "Charon", displayName: "Charon", descriptor: "Deep, authoritative"),
        .init(id: "Aoede",  displayName: "Aoede",  descriptor: "Calm, smooth"),
        .init(id: "Leda",   displayName: "Leda",   descriptor: "Bright, energetic"),
        .init(id: "Orus",   displayName: "Orus",   descriptor: "Steady, grounded"),
        .init(id: "Zephyr", displayName: "Zephyr", descriptor: "Light, breezy"),
        .init(id: "Fenrir", displayName: "Fenrir", descriptor: "Bold, intense"),
    ]

    static func named(_ id: String) -> GeminiVoice {
        catalog.first { $0.id == id } ?? catalog[0]
    }
}
