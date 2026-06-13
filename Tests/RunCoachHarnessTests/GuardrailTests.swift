import Testing
@testable import RunCoachHarness

// MARK: - Input guardrail

@Suite("InputGuard")
struct InputGuardTests {

    @Test("plausible telemetry passes")
    func plausiblePasses() {
        let t = RunTelemetry(
            elapsed: 600, distanceMeters: 2000,
            currentPaceSecPerKm: 300, heartRate: 150, heartRateZone: "cardio"
        )
        #expect(InputGuard.check(t).passed)
    }

    @Test("heart rate too high is blocked")
    func highHeartRateBlocked() {
        let t = RunTelemetry(heartRate: 240)
        let result = InputGuard.check(t)
        #expect(!result.passed)
        #expect(result.reason?.contains("heart rate") == true)
    }

    @Test("heart rate too low is blocked")
    func lowHeartRateBlocked() {
        #expect(!InputGuard.check(RunTelemetry(heartRate: 20)).passed)
    }

    @Test("impossibly fast pace is blocked")
    func impossiblePaceBlocked() {
        // 90 s/km == 1:30/km, faster than the 2:00/km floor.
        let result = InputGuard.check(RunTelemetry(currentPaceSecPerKm: 90))
        #expect(!result.passed)
        #expect(result.reason?.contains("pace") == true)
    }

    @Test("negative distance is blocked")
    func negativeDistanceBlocked() {
        #expect(!InputGuard.check(RunTelemetry(distanceMeters: -5)).passed)
    }

    @Test("missing optional metrics still pass")
    func sparseSnapshotPasses() {
        #expect(InputGuard.check(RunTelemetry(distanceMeters: 100)).passed)
    }
}

// MARK: - Output guardrail: [playful] token

@Suite("OutputGuard.stripPlayful")
struct StripPlayfulTests {

    @Test("strips the prefix and flags playful")
    func stripsPrefix() {
        let r = OutputGuard.stripPlayful("[playful] You crushed it!")
        #expect(r.isPlayful)
        #expect(r.text == "You crushed it!")
    }

    @Test("case-insensitive prefix")
    func caseInsensitive() {
        #expect(OutputGuard.stripPlayful("[PLAYFUL] go").isPlayful)
    }

    @Test("no prefix leaves text untouched")
    func noPrefix() {
        let r = OutputGuard.stripPlayful("  Keep it steady.  ")
        #expect(!r.isPlayful)
        #expect(r.text == "Keep it steady.")
    }
}

// MARK: - Output guardrail: validation

@Suite("OutputGuard.validate")
struct ValidateTests {

    @Test("clean line passes and is returned")
    func cleanPasses() {
        let result = OutputGuard.validate("Nice and smooth, keep that cadence.", recent: [])
        #expect(result.passed)
        #expect(result.text == "Nice and smooth, keep that cadence.")
    }

    @Test("empty output is blocked")
    func emptyBlocked() {
        #expect(!OutputGuard.validate("", recent: []).passed)
    }

    @Test("over 280 characters is blocked")
    func tooLongBlocked() {
        let long = String(repeating: "a", count: 281)
        let result = OutputGuard.validate(long, recent: [])
        #expect(!result.passed)
        #expect(result.reason?.contains("too long") == true)
    }

    @Test("exactly 280 characters passes")
    func boundaryPasses() {
        #expect(OutputGuard.validate(String(repeating: "a", count: 280), recent: []).passed)
    }

    @Test("emoji is blocked")
    func emojiBlocked() {
        let result = OutputGuard.validate("Great job 🎉", recent: [])
        #expect(!result.passed)
        #expect(result.reason == "contains emoji")
    }

    @Test("hashtag is blocked")
    func hashtagBlocked() {
        #expect(!OutputGuard.validate("Keep going #running", recent: []).passed)
    }

    @Test("medical claims are blocked", arguments: [
        "I think you're having a heart attack",
        "This is a medical emergency",
        "Let me diagnose that pain",
        "You should stop running immediately",
    ])
    func medicalBlocked(line: String) {
        let result = OutputGuard.validate(line, recent: [])
        #expect(!result.passed)
        #expect(result.reason?.contains("medical") == true)
    }

    @Test("a repeated opener is blocked")
    func repeatedOpenerBlocked() {
        let recent = ["Nice and smooth, hold the pace."]
        // Same first 14 characters as the recent line.
        let result = OutputGuard.validate("Nice and smooth, different ending.", recent: recent)
        #expect(!result.passed)
        #expect(result.reason?.contains("repeats") == true)
    }

    @Test("a fresh opener passes despite recent history")
    func freshOpenerPasses() {
        let recent = ["Nice and smooth, hold the pace."]
        #expect(OutputGuard.validate("Strong finish coming up, dig in.", recent: recent).passed)
    }
}
