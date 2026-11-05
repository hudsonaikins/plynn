import AVFoundation
import FluidAudio

/// Streaming ASR over FluidAudio's Parakeet Unified streaming manager, with a
/// VAD silence gate at finish() so silence-only sessions can never hallucinate
/// text. Reusable across sessions: call start() before each dictation.
public actor StreamingTranscriber: DictationEngine {
    public nonisolated let displayName = "Parakeet (local)"
    /// Keep one model graph warm for predictable memory and startup behavior.
    /// Change this only after a measured replacement is accepted.
    private static let variant = StreamingModelVariant.parakeetUnified1120ms
    private var manager: StreamingUnifiedAsrManager?
    private var vad: VadManager?
    private var sessionSamples: [Float] = []
    private var desiredVocabulary: [DictationVocabularyTerm] = []
    private var configuredVocabulary: [DictationVocabularyTerm] = []
    private var ctcModels: CtcModels?
    private var vocabularyLoadTask: Task<Void, Never>?

    /// parakeetUnified1120ms shares its model repo with the offline batch path —
    /// one download covers both — and beats the 2080ms tier on WER and latency.
    public init() {}

    /// Load models (idempotent) and reset for a new session.
    public func start() async throws {
        if manager == nil {
            manager = StreamingUnifiedAsrManager(
                config: Self.variant.unifiedConfig ?? UnifiedConfig())
            try await manager!.loadModels()
        }
        try await configureVocabularyIfReady()
        try await manager!.reset()
        sessionSamples.removeAll(keepingCapacity: true)
    }

    /// Update vocabulary without delaying microphone startup. The auxiliary
    /// CTC model downloads once in the background; boosting starts next session.
    public func setVocabulary(_ terms: [DictationVocabularyTerm]) async {
        var seen: Set<String> = []
        desiredVocabulary = Array(terms.filter {
            seen.insert($0.text.lowercased()).inserted
        }.prefix(64))
        guard !desiredVocabulary.isEmpty, ctcModels == nil, vocabularyLoadTask == nil else {
            return
        }
        vocabularyLoadTask = Task { [weak self] in
            do {
                let models = try await CtcModels.downloadAndLoad(variant: .ctc110m)
                await self?.finishVocabularyLoad(models)
            } catch {
                NSLog("plynn: vocabulary model unavailable: %@", String(describing: error))
                await self?.finishVocabularyLoad(nil)
            }
        }
    }

    private func finishVocabularyLoad(_ models: CtcModels?) {
        ctcModels = models
        vocabularyLoadTask = nil
        if models != nil { NSLog("plynn: local vocabulary boosting ready") }
    }

    private func configureVocabularyIfReady() async throws {
        guard desiredVocabulary != configuredVocabulary,
              let manager, let ctcModels else { return }
        let terms = desiredVocabulary.map {
            CustomVocabularyTerm(text: $0.text, aliases: $0.aliases)
        }
        try await manager.configureVocabularyBoosting(
            vocabulary: CustomVocabularyContext(terms: terms),
            ctcModels: ctcModels)
        configuredVocabulary = desiredVocabulary
        NSLog("plynn: vocabulary boosting configured with %d terms", terms.count)
    }

    public func setPartialCallback(_ callback: @escaping @Sendable (String) -> Void) async {
        await manager?.setPartialTranscriptCallback(callback)
    }

    /// Feed 16 kHz mono Float32 samples; partial transcripts fire via the callback.
    public func append(samples: [Float]) async throws {
        guard let manager else { return }
        sessionSamples.append(contentsOf: samples)
        let buffer = AVAudioPCMBuffer(
            pcmFormat: AudioFile.targetFormat, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        try await manager.appendAudio(buffer)
        try await manager.processBufferedAudio()
    }

    /// Trailing silence fed before finish(): flushes the streaming encoder's
    /// look-ahead window so words spoken right before release aren't dropped —
    /// the same short-utterance fix as the batch path, and also pads very short
    /// sessions up to the 2 s floor the model needs to emit anything at all.
    private static let flushPadSamples = 20_000  // 1.25 s
    private static let minSessionSamples = 32_000  // 2 s

    /// Flush and return the final transcript — empty string if VAD saw no speech.
    public func finish() async throws -> String {
        guard let manager else { return "" }
        let spoken = sessionSamples  // VAD judges only real mic audio, not padding
        var pad = Self.flushPadSamples
        if spoken.count + pad < Self.minSessionSamples { pad = Self.minSessionSamples - spoken.count }
        try await append(samples: [Float](repeating: 0, count: pad))
        sessionSamples = spoken
        let text = try await manager.finish()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        if try await hasSpeech(in: sessionSamples) { return text }
        return ""
    }

    private func hasSpeech(in samples: [Float]) async throws -> Bool {
        guard !samples.isEmpty else { return false }
        if vad == nil { vad = try await VadManager() }
        let results = try await vad!.process(samples)
        return results.contains { $0.isVoiceActive }
    }
}
