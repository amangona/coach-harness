import SwiftUI
import RunCoachHarness

/// Shows the runner's journalled history — the persistent Memory the coach learns from.
struct RunHistoryView: View {
    @ObservedObject var vm: CoachViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var runs: [RunMemory] = []

    var body: some View {
        NavigationStack {
            List {
                if runs.isEmpty {
                    Text("No runs yet. Finish a run and it'll be saved here — the coach uses it next time.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(runs) { run in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("\(Display.dist(run.distanceMeters)) km").font(.headline)
                                Spacer()
                                Text(run.date, style: .date).font(.caption).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 6) {
                                Text(Display.dur(run.duration))
                                Text("· \(Display.pace(run.avgPaceSecPerKm))/km").foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                            ForEach(run.notes, id: \.self) { note in
                                Text("• \(note)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Run History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if !runs.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear") { Task { await vm.clearHistory(); runs = await vm.loadHistory() } }
                    }
                }
            }
            .task { runs = await vm.loadHistory() }
        }
    }
}
