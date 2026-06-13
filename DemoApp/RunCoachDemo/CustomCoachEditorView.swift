import SwiftUI
import RunCoachHarness

/// Custom coach editor: name, free-text personality, and a Google (Gemini)
/// voice picker with live preview.
struct CustomCoachEditorView: View {
    @ObservedObject var vm: CoachViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var instructions: String
    @State private var voiceName: String
    @State private var styleHint: String
    @State private var previewing = false

    private let styles = ["neutral", "enthusiastic", "calm", "intense", "playful"]

    init(vm: CoachViewModel) {
        self.vm = vm
        let c = vm.customCoach
        _name = State(initialValue: c?.name ?? "My Coach")
        _instructions = State(initialValue: c?.instructions
            ?? "Speak like an encouraging trail-running buddy — warm, a little funny, never preachy.")
        _voiceName = State(initialValue: c?.voiceName ?? "Kore")
        _styleHint = State(initialValue: c?.styleHint ?? "enthusiastic")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Coach name", text: $name)
                }

                Section("Personality") {
                    TextEditor(text: $instructions)
                        .frame(minHeight: 120)
                        .font(.body)
                    Text("Describe how the coach talks — tone, energy, vocabulary. This becomes the LLM persona directive.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Voice — Google TTS") {
                    Picker("Voice", selection: $voiceName) {
                        ForEach(GeminiVoice.catalog) { voice in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(voice.displayName)
                                Text(voice.descriptor).font(.caption).foregroundStyle(.secondary)
                            }.tag(voice.id)
                        }
                    }
                    .pickerStyle(.inline)

                    Button {
                        previewing = true
                        Task { await vm.previewVoice(voiceName: voiceName, instructions: instructions); previewing = false }
                    } label: {
                        Label(previewing ? "Playing…" : "Preview voice", systemImage: "speaker.wave.2.fill")
                    }
                    .disabled(previewing)

                    if !vm.googleVoicesAvailable {
                        Text("No Gemini API key set — preview & playback use an Apple voice. Add a key (Secrets) to hear Google voices.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Speaking style") {
                    Picker("Style", selection: $styleHint) {
                        ForEach(styles, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                }

                if vm.customCoach != nil {
                    Section {
                        Button("Delete custom coach", role: .destructive) {
                            vm.customCoach = nil
                            if vm.personaId == "custom" { vm.personaId = CoachPersona.motivational.id }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Custom Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        vm.customCoach = CoachViewModel.CustomCoach(
                            name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "My Coach" : name,
                            instructions: instructions,
                            voiceName: voiceName,
                            styleHint: styleHint
                        )
                        vm.personaId = "custom"
                        dismiss()
                    }
                }
            }
        }
    }
}
