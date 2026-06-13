import SwiftUI
import RunCoachHarness

struct ContentView: View {
    @StateObject private var vm = CoachViewModel()
    @State private var showEditor = false
    @State private var showSettings = false
    @State private var showHistory = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    metricsCard
                    coachBubble
                    setupCard
                    startButton
                    observabilityCard
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("RunCoach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "key.fill") }
                }
            }
            .sheet(isPresented: $showEditor) { CustomCoachEditorView(vm: vm) }
            .sheet(isPresented: $showSettings) { SettingsView(vm: vm) }
            .sheet(isPresented: $showHistory) { RunHistoryView(vm: vm) }
        }
    }

    // MARK: Hero metrics

    private var metricsCard: some View {
        HStack(spacing: 0) {
            metric("Distance", Display.dist(vm.distanceMeters), "km")
            divider
            metric("Time", Display.dur(vm.elapsed), nil)
            divider
            metric("Pace", Display.pace(vm.paceSecPerKm), "/km")
            divider
            metric("BPM", vm.heartRate.map { "\(Int($0))" } ?? "—", nil)
        }
        .card()
    }

    private func metric(_ label: String, _ value: String, _ unit: String?) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let unit { Text(unit).font(.caption2).foregroundStyle(.secondary) }
            }
            CapsLabel(text: label)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1, height: 34)
    }

    // MARK: Coach bubble

    private var coachBubble: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Color.brand.opacity(0.18)).frame(width: 36, height: 36)
                    Image(systemName: "figure.run").font(.subheadline.weight(.bold)).foregroundStyle(Color.brand)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(vm.persona.name).font(.headline)
                    Text(vm.persona.voiceName).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if !vm.currentStyle.isEmpty {
                    Text(vm.currentStyle)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(styleColor(vm.currentStyle).opacity(0.18), in: Capsule())
                        .foregroundStyle(styleColor(vm.currentStyle))
                }
            }
            Text(vm.currentLine)
                .font(.title3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.snappy, value: vm.currentLine)
        }
        .card()
    }

    // MARK: Setup (coach + goal + source + speak)

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Coach
            HStack {
                CapsLabel(text: "Coach")
                Spacer()
                Picker("Coach", selection: $vm.personaId) {
                    ForEach(CoachPersona.builtins, id: \.id) { Text($0.name).tag($0.id) }
                    if let custom = vm.customCoach { Text("\(custom.name) (custom)").tag("custom") }
                }
                .labelsHidden()
                .tint(.brand)
                Button { showEditor = true } label: {
                    Image(systemName: vm.customCoach == nil ? "plus.circle.fill" : "slider.horizontal.3")
                }
            }
            .disabled(vm.running)

            // Goal
            VStack(alignment: .leading, spacing: 8) {
                CapsLabel(text: "Goal")
                SegmentedChips(options: [(.free, "Free"), (.distance, "Distance"), (.time, "Time")],
                               selection: $vm.goalKind, disabled: vm.running)
                switch vm.goalKind {
                case .free:
                    Text("Free run — no target, just coaching.")
                        .font(.caption).foregroundStyle(.secondary)
                case .distance:
                    ChipScroller(options: [1.0, 2.0, 3.0, 5.0, 8.0, 10.0].map { ($0, "\(Int($0)) km") },
                                 selection: $vm.goalDistanceKm, disabled: vm.running)
                case .time:
                    ChipScroller(options: [10.0, 15.0, 20.0, 30.0, 45.0, 60.0].map { ($0, "\(Int($0)) min") },
                                 selection: $vm.goalTimeMinutes, disabled: vm.running)
                }
            }

            // Telemetry source
            VStack(alignment: .leading, spacing: 8) {
                CapsLabel(text: "Telemetry")
                SegmentedChips(options: [(.simulated, "Simulated"), (.live, "Live GPS")],
                               selection: $vm.sourceKind, disabled: vm.running)
            }

            Toggle(isOn: $vm.speakAloud) {
                Label("Speak aloud", systemImage: "speaker.wave.2.fill").font(.subheadline)
            }
            .tint(.brand)
            .disabled(vm.running)
        }
        .card()
    }

    // MARK: Start / Stop

    private var startButton: some View {
        Button { vm.running ? vm.stop() : vm.start() } label: {
            Text(vm.running ? "STOP" : "START")
                .font(.title3.weight(.heavy))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
        }
        .background(Capsule().fill(vm.running ? Color.red : Color.brand))
        .shadow(color: (vm.running ? Color.red : Color.brand).opacity(0.45), radius: 16, y: 8)
        .buttonStyle(.plain)
        .animation(.snappy, value: vm.running)
    }

    // MARK: Observability

    private var observabilityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label("Observability", systemImage: "scope").font(.subheadline.weight(.semibold))
                Text(vm.usingRealEngine ? "Gemini" : "Mock")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background((vm.usingRealEngine ? Color.brand : Color.gray).opacity(0.18), in: Capsule())
                    .foregroundStyle(vm.usingRealEngine ? Color.brand : .secondary)
                Spacer()
                Text("\(vm.spokenCount) spoke · \(vm.skippedCount) skipped")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                stat("\(vm.totalTokens)", "tokens")
                stat(String(format: "$%.5f", vm.totalCost), "cost")
                stat("\(vm.avgLatencyMs)ms", "avg latency")
            }

            if !vm.traces.isEmpty {
                Divider()
                ForEach(Array(vm.traces.prefix(12).enumerated()), id: \.offset) { _, t in
                    traceRow(t)
                }
            }
        }
        .card()
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.subheadline.weight(.bold).monospacedDigit())
            CapsLabel(text: label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func traceRow(_ t: CoachTrace) -> some View {
        HStack(spacing: 8) {
            Circle().fill(t.decision == "spoke" ? Color.green : Color.orange).frame(width: 7, height: 7)
            Text(t.trigger).font(.caption.weight(.medium))
            Text(t.decision).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            if let tools = t.toolCalls, !tools.isEmpty {
                Text("🔧\(tools.count)").font(.caption2)
            }
            Spacer()
            Text("\(t.promptTokens + t.outputTokens)t")
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func styleColor(_ style: String) -> Color {
        switch style {
        case "enthusiastic": return .brand
        case "intense":      return .red
        case "calm":         return .teal
        case "playful":      return .purple
        case "whispered":    return .indigo
        default:             return .blue
        }
    }
}

/// Display formatting for the dashboard (metric / km).
enum Display {
    static func pace(_ secPerKm: Double?) -> String {
        guard let s = secPerKm, s > 0 else { return "—" }
        return String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
    }
    static func dist(_ m: Double) -> String { String(format: "%.2f", m / 1000) }
    static func dur(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

#Preview {
    ContentView()
}
