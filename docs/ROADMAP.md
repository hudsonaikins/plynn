# Plynn Roadmap

Fully local dictation for macOS. Everything on device, always.

## Shipped

- **Phases 0 to 1, core dictation:** hold fn dictation with streaming partials
  (Parakeet via FluidAudio on the Neural Engine), a VAD silence gate, the
  floating Liquid Glass indicator, secure field protection, Apple's
  SpeechTranscriber as the zero download onboarding engine, and paste with
  press enter support.
- **Phase 2, formatting:** an instant rules pass (spoken punctuation, new
  line, press enter) plus AI polish (fillers, self corrections, lists, per
  app tone) running on device. A latency gate keeps clean short dictations
  pasting instantly.
- **Phase 3, personalization:** a custom dictionary with aliases and CSV
  import, spoken snippets, dictation history and stats in local SQLite,
  automatic learning from your corrections, and Wispr Flow data import.

## Next

- **Phase 4, command mode and release polish**
  - Selection transforms with a before and after diff preview.
  - Generation at the cursor ("write a polite decline").
  - Onboarding practice exercises and the `plynn://` URL scheme.
  - Sparkle auto updates, notarized DMG, GitHub release pipeline.

- **Phase 5, power features**
  - **Benchmark the optional Granite MLX fallback.** Apple Intelligence remains
    the preferred polish engine; Granite 3.3 2B runs as a separate loopback
    service. Compare coding-dictation quality, latency, and memory use before
    enabling it by default or shipping a managed server.
  - A max accuracy re transcription pass (Whisper large v3 turbo) for noisy
    audio.
  - Dictionary boosting inside the recognizer itself (CTC keyword spotting,
    which needs FluidAudio's sliding window manager).
  - A scratchpad window, and meeting mode with speaker diarization.
  - Multilingual support (Parakeet v3 and Whisper).

## Never

- Cloud transcription, telemetry, accounts. Audio and text stay on the Mac.
