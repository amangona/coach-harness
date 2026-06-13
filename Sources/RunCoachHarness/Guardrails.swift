import Foundation

/// PILLAR: Guardrails ("bumper bowling"). Input guard → action → output guard.
public struct GuardrailResult: Sendable {
    public let passed: Bool
    public let reason: String?
    public let text: String     // sanitized text (when passing)

    public static func pass(_ text: String) -> GuardrailResult {
        GuardrailResult(passed: true, reason: nil, text: text)
    }
    public static func block(_ reason: String) -> GuardrailResult {
        GuardrailResult(passed: false, reason: reason, text: "")
    }
}

/// Reject garbage telemetry before the coach ever reacts to it.
public enum InputGuard {
    public static func check(_ t: RunTelemetry) -> GuardrailResult {
        if let hr = t.heartRate, hr > 0, (hr < 30 || hr > 230) {
            return .block("implausible heart rate: \(Int(hr)) bpm")
        }
        if let p = t.currentPaceSecPerKm, p > 0, p < 120 {
            return .block("implausible pace: faster than 2:00/km")
        }
        if t.distanceMeters < 0 || t.elapsed < 0 {
            return .block("negative distance/elapsed")
        }
        return .pass("")
    }
}

/// Enforce the brand/safety contract on the model's words before they are spoken.
public enum OutputGuard {
    /// Strip the internal `[playful]` control token, returning the clean text + flag.
    public static func stripPlayful(_ raw: String) -> (text: String, isPlayful: Bool) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("[playful]") {
            let body = trimmed.dropFirst("[playful]".count).trimmingCharacters(in: .whitespacesAndNewlines)
            return (body, true)
        }
        return (trimmed, false)
    }

    /// Validate already-stripped text against length / safety / anti-repeat rules.
    public static func validate(_ text: String, recent: [String]) -> GuardrailResult {
        if text.isEmpty { return .block("empty output") }
        if text.count > 280 { return .block("too long (\(text.count) chars)") }
        if containsEmoji(text) { return .block("contains emoji") }
        if text.contains("#") { return .block("contains hashtag") }

        let lowered = text.lowercased()
        let bannedMedical = ["diagnos", "heart attack", "medical emergency", "you should stop running"]
        for phrase in bannedMedical where lowered.contains(phrase) {
            return .block("possible medical claim: \"\(phrase)\"")
        }

        let opener = openerKey(text)
        for prior in recent where openerKey(prior) == opener {
            return .block("repeats a recent opener")
        }
        return .pass(text)
    }

    private static func openerKey(_ s: String) -> String {
        String(s.lowercased().prefix(14))
    }

    private static func containsEmoji(_ s: String) -> Bool {
        s.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.properties.isEmoji && $0.value > 0x238C }
    }
}
