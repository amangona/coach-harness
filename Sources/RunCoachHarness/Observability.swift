import Foundation

/// Token pricing (USD per 1M tokens). Defaults track Gemini 2.5 Flash.
public struct Pricing: Sendable {
    public let inputPerM: Double
    public let outputPerM: Double
    public init(inputPerM: Double, outputPerM: Double) {
        self.inputPerM = inputPerM
        self.outputPerM = outputPerM
    }
    public static let gemini25Flash = Pricing(inputPerM: 0.30, outputPerM: 2.50)
    public static let free = Pricing(inputPerM: 0, outputPerM: 0)

    public func cost(prompt: Int, output: Int) -> Double {
        Double(prompt) / 1_000_000 * inputPerM + Double(output) / 1_000_000 * outputPerM
    }
}

/// PILLAR: Observability. One record per meaningful tick — "if you can't see it,
/// you can't fix it."
public struct CoachTrace: Sendable, Codable {
    public let tick: Int
    public let elapsed: TimeInterval
    public let trigger: String
    public let decision: String       // "spoke" | "skipped: <reason>"
    public let promptTokens: Int
    public let outputTokens: Int
    public let latencyMs: Int
    public let costUSD: Double
    public let text: String?
}

public protocol Tracer: AnyObject, Sendable {
    func record(_ trace: CoachTrace)
    func summary() -> String
}

/// Prints a human line + a JSON line per record, and tallies run totals.
public final class ConsoleTracer: Tracer, @unchecked Sendable {
    private let lock = NSLock()
    private var traces: [CoachTrace] = []
    private let emitJSON: Bool

    public init(emitJSON: Bool = true) {
        self.emitJSON = emitJSON
    }

    public func record(_ trace: CoachTrace) {
        lock.lock()
        traces.append(trace)
        lock.unlock()

        let cost = String(format: "$%.6f", trace.costUSD)
        print("  📊 t=\(trace.tick) @\(Fmt.dur(trace.elapsed)) | \(trace.trigger) → \(trace.decision)"
              + " | tok \(trace.promptTokens)+\(trace.outputTokens) | \(trace.latencyMs)ms | \(cost)")

        if emitJSON, let data = try? JSONEncoder().encode(trace), let json = String(data: data, encoding: .utf8) {
            print("     " + json)
        }
    }

    public func summary() -> String {
        lock.lock(); let all = traces; lock.unlock()
        let spoke = all.filter { $0.decision == "spoke" }
        let skipped = all.filter { $0.decision != "spoke" }
        let pTok = all.reduce(0) { $0 + $1.promptTokens }
        let oTok = all.reduce(0) { $0 + $1.outputTokens }
        let cost = all.reduce(0.0) { $0 + $1.costUSD }
        let avgLatency = spoke.isEmpty ? 0 : spoke.reduce(0) { $0 + $1.latencyMs } / spoke.count

        var s = "──── observability summary ────\n"
        s += "decisions: \(all.count)  spoke: \(spoke.count)  skipped: \(skipped.count)\n"
        s += "tokens: \(pTok) in + \(oTok) out = \(pTok + oTok)\n"
        s += String(format: "cost: $%.6f   avg speak latency: %dms\n", cost, avgLatency)
        if !skipped.isEmpty {
            s += "skip reasons:\n"
            for t in skipped { s += "  - t=\(t.tick): \(t.decision)\n" }
        }
        return s
    }
}
