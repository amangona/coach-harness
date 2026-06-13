import Foundation

/// A single snapshot of the live run — the "world state" the harness sees on each tick.
/// In a real tracker this is assembled from location + heart-rate + run services; here
/// it is just a value type so any source can produce it.
public struct RunTelemetry: Sendable, Codable, Equatable {
    public var elapsed: TimeInterval          // seconds since run start (excludes pauses)
    public var distanceMeters: Double
    public var currentPaceSecPerKm: Double?
    public var lastSplitPaceSecPerKm: Double?
    public var heartRate: Double?
    public var heartRateZone: String?         // "rest" | "warmUp" | "fatBurn" | "cardio" | "peak"
    public var elevationGainMeters: Double
    public var completedSplits: Int           // count of finished 1km splits
    public var goalType: String?              // "distance" | "time" | nil (free run)
    public var goalTargetMeters: Double?      // for distance goals
    public var goalTargetSeconds: Double?     // for time goals
    public var isGoalReached: Bool
    public var isFinished: Bool               // the source signals the run is over

    public init(
        elapsed: TimeInterval = 0,
        distanceMeters: Double = 0,
        currentPaceSecPerKm: Double? = nil,
        lastSplitPaceSecPerKm: Double? = nil,
        heartRate: Double? = nil,
        heartRateZone: String? = nil,
        elevationGainMeters: Double = 0,
        completedSplits: Int = 0,
        goalType: String? = nil,
        goalTargetMeters: Double? = nil,
        goalTargetSeconds: Double? = nil,
        isGoalReached: Bool = false,
        isFinished: Bool = false
    ) {
        self.elapsed = elapsed
        self.distanceMeters = distanceMeters
        self.currentPaceSecPerKm = currentPaceSecPerKm
        self.lastSplitPaceSecPerKm = lastSplitPaceSecPerKm
        self.heartRate = heartRate
        self.heartRateZone = heartRateZone
        self.elevationGainMeters = elevationGainMeters
        self.completedSplits = completedSplits
        self.goalType = goalType
        self.goalTargetMeters = goalTargetMeters
        self.goalTargetSeconds = goalTargetSeconds
        self.isGoalReached = isGoalReached
        self.isFinished = isFinished
    }

    /// Fractional progress toward the goal (distance or time), or nil for a free run.
    public var goalProgress: Double? {
        switch goalType {
        case "distance":
            guard let target = goalTargetMeters, target > 0 else { return nil }
            return min(distanceMeters / target, 1.0)
        case "time":
            guard let target = goalTargetSeconds, target > 0 else { return nil }
            return min(elapsed / target, 1.0)
        default:
            return nil
        }
    }
}

/// What the runner is aiming for this session.
public enum RunGoal: Sendable, Equatable {
    case free
    case distance(meters: Double)
    case time(seconds: TimeInterval)
}

/// Why the coach is being asked to consider speaking. Drives priority + rate-limit bypass.
public enum CoachingTrigger: String, Sendable, Codable {
    case runStart
    case splitCompleted
    case heartRateZoneChange
    case cheerReceived
    case userSpoke
    case runEnd

    /// Higher interrupts lower.
    public var priority: Int {
        switch self {
        case .userSpoke:           return 6
        case .heartRateZoneChange: return 5
        case .cheerReceived:       return 4
        case .splitCompleted:      return 2
        case .runStart:            return 1
        case .runEnd:              return 0
        }
    }

    /// Moments important enough to skip the cooldown.
    public var bypassesRateLimit: Bool {
        switch self {
        case .runStart, .runEnd, .cheerReceived, .userSpoke: return true
        case .splitCompleted, .heartRateZoneChange:          return false
        }
    }
}

/// THE input seam. A production app conforms its live run to this; the demo ships
/// `SimulatedRun`. Either way the loop just consumes snapshots until the stream ends.
public protocol TelemetrySource: Sendable {
    func stream() -> AsyncStream<RunTelemetry>
}
