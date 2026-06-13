import Foundation

/// A demo `TelemetrySource`: synthesizes a ~5K run on an accelerated clock so the loop
/// has something live to coach without a device. Negative splits, HR drift, a final surge.
public struct SimulatedRun: TelemetrySource {
    public let targetMeters: Double
    public let tickMillis: Int          // wall-clock between emits
    public let runSecondsPerTick: Double // sim seconds advanced per tick
    public let basePaceSecPerKm: Double
    public let maxHeartRate: Double

    public init(
        targetMeters: Double = 5000,
        tickMillis: Int = 200,
        runSecondsPerTick: Double = 10,
        basePaceSecPerKm: Double = 330,
        maxHeartRate: Double = 190
    ) {
        self.targetMeters = targetMeters
        self.tickMillis = tickMillis
        self.runSecondsPerTick = runSecondsPerTick
        self.basePaceSecPerKm = basePaceSecPerKm
        self.maxHeartRate = maxHeartRate
    }

    public func stream() -> AsyncStream<RunTelemetry> {
        AsyncStream { continuation in
            let task = Task {
                var elapsed: Double = 0
                var distance: Double = 0

                while distance < targetMeters && !Task.isCancelled {
                    elapsed += runSecondsPerTick
                    let progress = distance / targetMeters

                    // Pace: easy warmup, a fast PR surge through the 3rd km, hard final surge.
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

                    let speed = 1000.0 / pace          // m/s
                    distance += speed * runSecondsPerTick
                    let clamped = min(distance, targetMeters)

                    let hr = 120 + progress * 55 + (progress > 0.9 ? 10 : 0)
                    let zone = SimulatedRun.zone(for: hr, maxHR: maxHeartRate)

                    continuation.yield(RunTelemetry(
                        elapsed: elapsed,
                        distanceMeters: clamped,
                        currentPaceSecPerKm: pace,
                        lastSplitPaceSecPerKm: pace,
                        heartRate: hr,
                        heartRateZone: zone,
                        elevationGainMeters: progress * 40,
                        completedSplits: Int(clamped / 1000),
                        goalType: "distance",
                        goalTargetMeters: targetMeters,
                        isGoalReached: false,
                        isFinished: false
                    ))

                    try? await Task.sleep(for: .milliseconds(tickMillis))
                }

                // Final, finished snapshot → triggers runEnd.
                continuation.yield(RunTelemetry(
                    elapsed: elapsed,
                    distanceMeters: targetMeters,
                    currentPaceSecPerKm: basePaceSecPerKm - 30,
                    lastSplitPaceSecPerKm: basePaceSecPerKm - 30,
                    heartRate: maxHeartRate * 0.92,
                    heartRateZone: "peak",
                    elevationGainMeters: 40,
                    completedSplits: Int(targetMeters / 1000),
                    goalType: "distance",
                    goalTargetMeters: targetMeters,
                    isGoalReached: true,
                    isFinished: true
                ))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
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
