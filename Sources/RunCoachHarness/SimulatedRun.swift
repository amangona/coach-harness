import Foundation

/// A demo `TelemetrySource`: synthesizes a run on an accelerated clock so the loop has
/// something live to coach without a device. Honors the chosen `RunGoal` — distance, time,
/// or a free run (ends after a default distance). Negative splits, HR drift, a final surge.
public struct SimulatedRun: TelemetrySource {
    public let goal: RunGoal
    public let tickMillis: Int
    public let runSecondsPerTick: Double
    public let basePaceSecPerKm: Double
    public let maxHeartRate: Double
    public let freeRunMeters: Double

    public init(
        goal: RunGoal = .distance(meters: 5000),
        tickMillis: Int = 200,
        runSecondsPerTick: Double = 10,
        basePaceSecPerKm: Double = 330,
        maxHeartRate: Double = 190,
        freeRunMeters: Double = 4000
    ) {
        self.goal = goal
        self.tickMillis = tickMillis
        self.runSecondsPerTick = runSecondsPerTick
        self.basePaceSecPerKm = basePaceSecPerKm
        self.maxHeartRate = maxHeartRate
        self.freeRunMeters = freeRunMeters
    }

    /// Distance used only to shape the pace curve (warmup / negative split / final surge).
    private var pacingDistance: Double {
        switch goal {
        case .distance(let m):  return m
        case .time(let s):      return 1000.0 / basePaceSecPerKm * s  // rough projected distance
        case .free:             return freeRunMeters
        }
    }

    public func stream() -> AsyncStream<RunTelemetry> {
        AsyncStream { continuation in
            let task = Task {
                var elapsed: Double = 0
                var distance: Double = 0
                let pacing = max(pacingDistance, 500)

                while !reachedEnd(distance: distance, elapsed: elapsed) && !Task.isCancelled {
                    elapsed += runSecondsPerTick
                    let progress = min(distance / pacing, 1.0)

                    let pace: Double
                    if progress < 0.1 {
                        pace = basePaceSecPerKm + 25            // warmup
                    } else if progress >= 0.4 && progress < 0.62 {
                        pace = basePaceSecPerKm - 45            // PR split (beats the 5:00/km best)
                    } else if progress > 0.9 {
                        pace = basePaceSecPerKm - 30            // final surge
                    } else {
                        pace = basePaceSecPerKm - progress * 15 // gentle negative split
                    }

                    let speed = 1000.0 / pace
                    distance += speed * runSecondsPerTick
                    let hr = 120 + progress * 55 + (progress > 0.9 ? 10 : 0)

                    continuation.yield(snapshot(
                        elapsed: elapsed,
                        distance: distance,
                        pace: pace,
                        hr: hr,
                        progress: progress,
                        finished: false
                    ))
                    try? await Task.sleep(for: .milliseconds(tickMillis))
                }

                // Final, finished snapshot.
                continuation.yield(snapshot(
                    elapsed: elapsed,
                    distance: distance,
                    pace: basePaceSecPerKm - 30,
                    hr: maxHeartRate * 0.92,
                    progress: 1.0,
                    finished: true
                ))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func reachedEnd(distance: Double, elapsed: Double) -> Bool {
        switch goal {
        case .distance(let m): return distance >= m
        case .time(let s):     return elapsed >= s
        case .free:            return distance >= freeRunMeters
        }
    }

    private func snapshot(elapsed: Double, distance: Double, pace: Double, hr: Double,
                          progress: Double, finished: Bool) -> RunTelemetry {
        var goalType: String?
        var targetMeters: Double?
        var targetSeconds: Double?
        var reached = false
        switch goal {
        case .distance(let m):
            goalType = "distance"; targetMeters = m; reached = distance >= m
        case .time(let s):
            goalType = "time"; targetSeconds = s; reached = elapsed >= s
        case .free:
            break
        }
        let cappedDistance = (goalType == "distance") ? min(distance, targetMeters ?? distance) : distance
        return RunTelemetry(
            elapsed: elapsed,
            distanceMeters: cappedDistance,
            currentPaceSecPerKm: pace,
            lastSplitPaceSecPerKm: pace,
            heartRate: hr,
            heartRateZone: SimulatedRun.zone(for: hr, maxHR: maxHeartRate),
            elevationGainMeters: progress * 40,
            completedSplits: Int(cappedDistance / 1000),
            goalType: goalType,
            goalTargetMeters: targetMeters,
            goalTargetSeconds: targetSeconds,
            isGoalReached: finished ? reached : false,
            isFinished: finished
        )
    }

    static func zone(for hr: Double, maxHR: Double) -> String {
        switch hr / maxHR * 100 {
        case ..<50:   return "rest"
        case 50..<60: return "warmUp"
        case 60..<70: return "fatBurn"
        case 70..<85: return "cardio"
        default:      return "peak"
        }
    }
}
