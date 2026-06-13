import Foundation

/// PILLAR: output. Turns the approved coaching text into "speech". The protocol lets the
/// demo print to console while a production app swaps in real TTS.
public protocol SpeechOutput: Sendable {
    func speak(_ text: String, style: String) async
}

/// Prints the line. Default for headless demos.
public struct ConsoleSpeech: SpeechOutput {
    public init() {}
    public func speak(_ text: String, style: String) async {
        print("  🔊 [\(style)] \(text)")
    }
}

/// Speaks aloud via macOS `/usr/bin/say` (fun for a live demo), and also prints.
public struct SaySpeech: SpeechOutput {
    public init() {}
    public func speak(_ text: String, style: String) async {
        print("  🔊 [\(style)] \(text)")
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = [text]
        try? process.run()
        process.waitUntilExit()
        #endif
    }
}
