import Foundation
import AVFoundation

/// Speaks a line aloud. Two implementations: Apple's on-device synth (fallback) and Gemini
/// TTS (real Google voices) when an API key is present.
protocol VoiceSynthesizer: Sendable {
    func speak(_ text: String) async
}

// MARK: - Apple (fallback, no key required)

final class AppleVoiceSynthesizer: NSObject, VoiceSynthesizer, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let synth = AVSpeechSynthesizer()
    private var done: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            done = cont
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            synth.speak(utterance)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        done?.resume(); done = nil
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        done?.resume(); done = nil
    }
}

// MARK: - Gemini TTS (real Google voices)

/// Synthesizes speech with a chosen Gemini voice via the TTS model, then plays the returned
/// PCM (wrapped as WAV) through AVAudioPlayer. Falls silent on any error so it never blocks.
final class GeminiVoiceSynthesizer: NSObject, VoiceSynthesizer, AVAudioPlayerDelegate, @unchecked Sendable {
    private let apiKey: String
    private let voiceName: String
    private let model = "gemini-2.5-flash-preview-tts"
    private var player: AVAudioPlayer?
    private var done: CheckedContinuation<Void, Never>?

    init(apiKey: String, voiceName: String) {
        self.apiKey = apiKey
        self.voiceName = voiceName
    }

    func speak(_ text: String) async {
        guard let pcm = await synthesize(text) else { return }
        let wav = GeminiVoiceSynthesizer.wav(pcm: pcm, sampleRate: 24_000)
        await playAndWait(wav)
    }

    // MARK: Network

    private struct Part: Codable {
        struct InlineData: Codable { let mimeType: String?; let data: String? }
        var text: String?
        var inlineData: InlineData?
    }
    private struct Content: Codable { let parts: [Part] }
    private struct PrebuiltVoiceConfig: Codable { let voiceName: String }
    private struct VoiceConfig: Codable { let prebuiltVoiceConfig: PrebuiltVoiceConfig }
    private struct SpeechConfig: Codable { let voiceConfig: VoiceConfig }
    private struct GenConfig: Codable { let responseModalities: [String]; let speechConfig: SpeechConfig }
    private struct Request: Codable { let contents: [Content]; let generationConfig: GenConfig }
    private struct Candidate: Codable { let content: Content? }
    private struct Response: Codable { let candidates: [Candidate]? }

    private func synthesize(_ text: String) async -> Data? {
        let urlStr = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlStr) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = Request(
            contents: [Content(parts: [Part(text: text, inlineData: nil)])],
            generationConfig: GenConfig(
                responseModalities: ["AUDIO"],
                speechConfig: SpeechConfig(voiceConfig: VoiceConfig(prebuiltVoiceConfig: PrebuiltVoiceConfig(voiceName: voiceName)))
            )
        )
        guard let data = try? JSONEncoder().encode(body) else { return nil }
        req.httpBody = data

        guard let (respData, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(Response.self, from: respData),
              let b64 = decoded.candidates?.first?.content?.parts.compactMap({ $0.inlineData?.data }).first,
              let pcm = Data(base64Encoded: b64) else {
            return nil
        }
        return pcm
    }

    // MARK: Playback

    @MainActor
    private func playAndWait(_ data: Data) async {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            do {
                let p = try AVAudioPlayer(data: data)
                p.delegate = self
                player = p
                done = cont
                p.play()
            } catch {
                cont.resume()
            }
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        done?.resume(); done = nil
    }

    // MARK: PCM → WAV (16-bit mono)

    static func wav(pcm: Data, sampleRate: Int) -> Data {
        let channels: UInt16 = 1
        let bits: UInt16 = 16
        let blockAlign = channels * bits / 8
        let byteRate = UInt32(sampleRate) * UInt32(blockAlign)
        let dataSize = UInt32(pcm.count)

        var h = Data()
        func str(_ s: String) { h.append(s.data(using: .ascii)!) }
        func u32(_ v: UInt32) { var x = v.littleEndian; h.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; h.append(Data(bytes: &x, count: 2)) }

        str("RIFF"); u32(36 + dataSize); str("WAVE")
        str("fmt "); u32(16); u16(1); u16(channels); u32(UInt32(sampleRate)); u32(byteRate); u16(blockAlign); u16(bits)
        str("data"); u32(dataSize)

        var out = h
        out.append(pcm)
        return out
    }
}
