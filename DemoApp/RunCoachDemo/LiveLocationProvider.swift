import Foundation
import CoreLocation
import RunCoachHarness

/// Real-GPS telemetry: accumulates distance / pace / splits from CoreLocation and hands a
/// `RunTelemetry` snapshot to the harness on demand. Heart rate isn't available from
/// CoreLocation, so those fields stay nil in live mode.
///
/// To exercise this in the Simulator, set a route: Xcode ▸ Debug ▸ Simulate Location, or
/// `xcrun simctl location <udid> start --speed 3 <lat,lon> <lat,lon> …`.
final class LiveLocationProvider: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private let lock = NSLock()

    private var startDate: Date?
    private var lastLocation: CLLocation?
    private var totalDistance: Double = 0
    private var elevationGain: Double = 0
    private var paceSecPerKm: Double?
    private var splits: Int = 0
    private var finished = false
    private var goal: RunGoal = .free

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5
        manager.activityType = .fitness
    }

    func start(goal: RunGoal = .free) {
        lock.lock()
        self.goal = goal
        startDate = Date()
        totalDistance = 0; elevationGain = 0; splits = 0
        lastLocation = nil; paceSecPerKm = nil; finished = false
        lock.unlock()
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        lock.lock(); finished = true; lock.unlock()
    }

    /// Snapshot the accumulated state for the harness's polling source.
    func snapshot() async -> RunTelemetry {
        lock.lock(); defer { lock.unlock() }
        let elapsed = startDate.map { Date().timeIntervalSince($0) } ?? 0

        var goalType: String?
        var targetMeters: Double?
        var targetSeconds: Double?
        var reached = false
        switch goal {
        case .distance(let m):
            goalType = "distance"; targetMeters = m; reached = totalDistance >= m
        case .time(let s):
            goalType = "time"; targetSeconds = s; reached = elapsed >= s
        case .free:
            break
        }

        return RunTelemetry(
            elapsed: elapsed,
            distanceMeters: totalDistance,
            currentPaceSecPerKm: paceSecPerKm,
            lastSplitPaceSecPerKm: paceSecPerKm,
            heartRate: nil,
            heartRateZone: nil,
            elevationGainMeters: elevationGain,
            completedSplits: splits,
            goalType: goalType,
            goalTargetMeters: targetMeters,
            goalTargetSeconds: targetSeconds,
            isGoalReached: reached,
            isFinished: finished
        )
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lock.lock(); defer { lock.unlock() }
        for loc in locations where loc.horizontalAccuracy >= 0 && loc.horizontalAccuracy < 50 {
            if let prev = lastLocation {
                let step = loc.distance(from: prev)
                if step.isFinite, step >= 0 {
                    totalDistance += step
                    let climb = loc.altitude - prev.altitude
                    if climb > 0 { elevationGain += climb }
                }
            }
            if loc.speed > 0.3 {
                paceSecPerKm = 1000.0 / loc.speed
            }
            splits = Int(totalDistance / 1000)
            lastLocation = loc
        }
    }
}
