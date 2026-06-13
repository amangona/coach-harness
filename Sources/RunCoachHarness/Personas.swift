import Foundation

/// PILLAR: Memory (customization surface).
/// A coach persona — either a built-in or a user-authored custom coach. `instructions`
/// is the free-text directive appended to the base system prompt; this is what makes
/// each coach feel different.
public struct CoachPersona: Sendable, Codable, Equatable {
    public let id: String
    public let name: String
    public let voiceName: String       // a TTS voice id
    public let styleHint: String       // default prosody for this coach
    public let instructions: String    // LLM directive defining the persona

    public init(id: String, name: String, voiceName: String, styleHint: String, instructions: String) {
        self.id = id
        self.name = name
        self.voiceName = voiceName
        self.styleHint = styleHint
        self.instructions = instructions
    }

    public static let motivational = CoachPersona(
        id: "motivational", name: "Max", voiceName: "Kore", styleHint: "enthusiastic",
        instructions: "Speak like an upbeat motivational coach — energetic, positive, push the runner forward with confidence."
    )
    public static let calmZen = CoachPersona(
        id: "calmZen", name: "Aya", voiceName: "Aoede", styleHint: "calm",
        instructions: "Speak like a calm zen coach — short, mindful, never shouty. Breathe with them."
    )
    public static let drillSergeant = CoachPersona(
        id: "drillSergeant", name: "Sergeant Cole", voiceName: "Charon", styleHint: "intense",
        instructions: "Speak like a tough drill sergeant — direct, no-nonsense, demanding but fair. Short sharp commands."
    )
    public static let friendlyPacer = CoachPersona(
        id: "friendlyPacer", name: "Sam", voiceName: "Puck", styleHint: "playful",
        instructions: "Speak like a friendly running buddy at the same pace — supportive, conversational, like a friend."
    )

    public static let builtins: [CoachPersona] = [motivational, calmZen, drillSergeant, friendlyPacer]

    /// Build a fully custom coach from user input.
    public static func custom(name: String, voiceName: String, styleHint: String, instructions: String) -> CoachPersona {
        CoachPersona(id: "custom", name: name, voiceName: voiceName, styleHint: styleHint, instructions: instructions)
    }
}
