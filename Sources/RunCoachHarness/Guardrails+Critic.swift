import Foundation

/// PILLAR: Guardrails — the LLM-cascade tier the lecture described ("you may want another
/// LLM to validate"). Runs AFTER the cheap deterministic `OutputGuard`, as a second opinion
/// on whether a line is safe and on-brand before it's spoken.
public protocol OutputCritic: Sendable {
    func review(_ text: String, persona: CoachPersona) async -> GuardrailResult
}

/// Default: approve everything (used when no critic is configured / offline).
public struct NoOpCritic: OutputCritic {
    public init() {}
    public func review(_ text: String, persona: CoachPersona) async -> GuardrailResult { .pass(text) }
}

/// Uses any `LLMClient` as a strict reviewer. Fail-OPEN by design: if the critic errors or
/// returns something unparseable, we don't silence the coach — we let the line through (the
/// deterministic guard already passed it). That tradeoff is deliberate; flip it if safety
/// outweighs availability for your use case.
public struct LLMOutputCritic: OutputCritic {
    private let client: LLMClient
    public init(client: LLMClient) { self.client = client }

    public func review(_ text: String, persona: CoachPersona) async -> GuardrailResult {
        let system =
            "You are a strict safety/brand reviewer for a running-coach app. Approve a message " +
            "ONLY if ALL hold: it gives NO medical advice or diagnosis, it is under 280 characters, " +
            "it is encouraging and non-abusive, and it is consistent with the coach persona. " +
            "Reply with EXACTLY 'PASS' or 'BLOCK: <short reason>'."
        let user = "Coach persona: \(persona.instructions)\nMessage to review: \"\(text)\""

        guard let response = try? await client.generate(system: system, user: user) else {
            return .pass(text)   // fail-open
        }
        let verdict = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if verdict.uppercased().hasPrefix("PASS") { return .pass(text) }
        if verdict.uppercased().hasPrefix("BLOCK") {
            let reason = verdict.dropFirst("BLOCK".count).drop(while: { $0 == ":" || $0 == " " })
            return .block("critic: \(reason.isEmpty ? "rejected" : String(reason))")
        }
        return .pass(text)       // unparseable → fail-open
    }
}
