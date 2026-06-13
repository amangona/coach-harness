import Testing
import Foundation
@testable import RunCoachHarness

@Suite("JournalScoring.rank")
struct JournalRecallTests {

    private func day(_ offset: Int) -> Date {
        // Fixed reference date so tests are deterministic.
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86_400)
    }

    private var runs: [RunMemory] {
        [
            RunMemory(id: "a", date: day(0), distanceMeters: 5000, duration: 1650, avgPaceSecPerKm: 330,
                      notes: ["Faded on the final hill"]),
            RunMemory(id: "b", date: day(2), distanceMeters: 5000, duration: 1600, avgPaceSecPerKm: 320,
                      notes: ["Negative split, strong finish"]),
            RunMemory(id: "c", date: day(4), distanceMeters: 10000, duration: 3300, avgPaceSecPerKm: 330,
                      notes: ["Easy long run"]),
        ]
    }

    @Test("keyword match wins over pure recency")
    func keywordWins() {
        let result = JournalScoring.rank(runs, query: "hill fade", limit: 1)
        #expect(result.first?.id == "a")        // 'a' has the hill note though it's oldest
    }

    @Test("empty query returns most recent first")
    func emptyReturnsRecent() {
        let result = JournalScoring.rank(runs, query: "", limit: 3)
        #expect(result.first?.id == "c")        // newest by date
    }

    @Test("limit caps the result count")
    func limitCaps() {
        #expect(JournalScoring.rank(runs, query: "", limit: 2).count == 2)
    }
}

@Suite("RunnerProfile.derived")
struct ProfileDerivationTests {

    @Test("empty history yields an empty profile with the name preserved")
    func emptyHistory() {
        let profile = RunnerProfile.derived(from: [], name: "Abe")
        #expect(profile.name == "Abe")
        #expect(profile.avgPaceSecPerKm == nil)
    }

    @Test("averages distance and pace, takes best split as the minimum")
    func averages() {
        let runs = [
            RunMemory(date: Date(timeIntervalSince1970: 1), distanceMeters: 4000, duration: 1320, avgPaceSecPerKm: 330, bestSplitPaceSecPerKm: 315),
            RunMemory(date: Date(timeIntervalSince1970: 2), distanceMeters: 6000, duration: 1980, avgPaceSecPerKm: 330, bestSplitPaceSecPerKm: 300),
        ]
        let profile = RunnerProfile.derived(from: runs, name: nil)
        #expect(profile.avgDistanceMeters == 5000)
        #expect(profile.avgPaceSecPerKm == 330)
        #expect(profile.bestSplitPaceSecPerKm == 300)
    }
}

@Suite("InMemoryRunJournal")
struct JournalStoreTests {

    @Test("add then recall round-trips")
    func addRecall() async {
        let journal = InMemoryRunJournal()
        await journal.add(RunMemory(date: Date(timeIntervalSince1970: 1), distanceMeters: 5000, duration: 1650, avgPaceSecPerKm: 330, notes: ["tempo run"]))
        let all = await journal.allRuns()
        #expect(all.count == 1)
        let hit = await journal.recall(query: "tempo", limit: 3)
        #expect(hit.first?.notes.first == "tempo run")
    }
}
