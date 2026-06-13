import Foundation

/// PILLAR: Memory (persistent, cross-run).
/// One past run the coach can learn from. `notes` hold the human-meaningful events —
/// "faded on the final hill", "PR on split 3" — which is what makes recall useful.
public struct RunMemory: Sendable, Codable, Identifiable {
    public var id: String
    public var date: Date
    public var distanceMeters: Double
    public var duration: TimeInterval
    public var avgPaceSecPerKm: Double
    public var bestSplitPaceSecPerKm: Double?
    public var elevationGainMeters: Double
    public var notes: [String]

    public init(
        id: String = UUID().uuidString,
        date: Date,
        distanceMeters: Double,
        duration: TimeInterval,
        avgPaceSecPerKm: Double,
        bestSplitPaceSecPerKm: Double? = nil,
        elevationGainMeters: Double = 0,
        notes: [String] = []
    ) {
        self.id = id
        self.date = date
        self.distanceMeters = distanceMeters
        self.duration = duration
        self.avgPaceSecPerKm = avgPaceSecPerKm
        self.bestSplitPaceSecPerKm = bestSplitPaceSecPerKm
        self.elevationGainMeters = elevationGainMeters
        self.notes = notes
    }
}

/// A store of past runs the coach can write to and recall from.
public protocol RunJournal: Sendable {
    func allRuns() async -> [RunMemory]
    func add(_ run: RunMemory) async
    func recall(query: String, limit: Int) async -> [RunMemory]
    func removeAll() async
}

public extension RunJournal {
    func recall(query: String) async -> [RunMemory] { await recall(query: query, limit: 3) }
}

/// Relevance ranking for recall: keyword overlap on notes, blended with recency. Deliberately
/// simple (no embeddings) but real — empty query returns the most recent runs.
public enum JournalScoring {
    public static func rank(_ runs: [RunMemory], query: String, limit: Int) -> [RunMemory] {
        let terms = query.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let byRecency = runs.sorted { $0.date > $1.date }

        let scored = byRecency.enumerated().map { index, run -> (RunMemory, Double) in
            let hay = run.notes.joined(separator: " ").lowercased()
            let keyword = terms.reduce(0.0) { $0 + (hay.contains($1) ? 1.0 : 0.0) }
            let recency = 1.0 / Double(index + 1)
            return (run, keyword * 2.0 + recency)
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }
}

public extension RunnerProfile {
    /// Derive a profile from journalled runs (most recent 10), instead of hardcoding it.
    static func derived(from runs: [RunMemory], name: String? = nil) -> RunnerProfile {
        guard !runs.isEmpty else { return RunnerProfile(name: name) }
        let recent = runs.sorted { $0.date > $1.date }.prefix(10)
        let count = Double(recent.count)
        return RunnerProfile(
            name: name,
            avgDistanceMeters: recent.map(\.distanceMeters).reduce(0, +) / count,
            avgPaceSecPerKm: recent.map(\.avgPaceSecPerKm).reduce(0, +) / count,
            bestSplitPaceSecPerKm: recent.compactMap(\.bestSplitPaceSecPerKm).min()
        )
    }
}

/// JSON-file-backed journal — persists across runs and launches, so the coach genuinely
/// accumulates knowledge of the runner over time.
public actor FileRunJournal: RunJournal {
    private let url: URL
    private var cache: [RunMemory]

    public init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let runs = try? JSONDecoder().decode([RunMemory].self, from: data) {
            cache = runs
        } else {
            cache = []
        }
    }

    public static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("run_journal.json")
    }

    public func allRuns() async -> [RunMemory] { cache }

    public func add(_ run: RunMemory) async {
        cache.append(run)
        persist()
    }

    public func recall(query: String, limit: Int) async -> [RunMemory] {
        JournalScoring.rank(cache, query: query, limit: limit)
    }

    public func removeAll() async {
        cache = []
        persist()
    }

    private func persist() {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

/// In-memory journal — for tests and offline demos (seedable with sample history).
public actor InMemoryRunJournal: RunJournal {
    private var runs: [RunMemory]
    public init(seed: [RunMemory] = []) { runs = seed }
    public func allRuns() async -> [RunMemory] { runs }
    public func add(_ run: RunMemory) async { runs.append(run) }
    public func recall(query: String, limit: Int) async -> [RunMemory] {
        JournalScoring.rank(runs, query: query, limit: limit)
    }
    public func removeAll() async { runs = [] }
}
