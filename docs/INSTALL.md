# Installing Plynn

## For users

1. **Download** `Plynn.dmg` from GitHub Releases (a Homebrew cask is on the way).
2. **Drag Plynn to Applications.** Standard DMG window with an Applications shortcut.
3. **First launch.** Gatekeeper checks the notarization ticket, so there are no warnings to click through.
4. **Onboarding** walks you through the two permissions Plynn needs:
   - **Microphone** (a system prompt) so it can hear you.
   - **Accessibility** (a System Settings deep link) for the fn hotkey and pasting.
5. **The Parakeet speech model downloads in the background** (about 1 GB). Dictation works with Apple's built-in speech engine while it downloads. AI polish uses Apple Intelligence when enabled; otherwise it can use an optional local Granite MLX server.
6. Optional: turn on **Launch at login** in Settings.

Updates arrive through Sparkle: the app tells you when a new version exists and installs it in one click.

## Optional Granite fallback for local testing

Install `mlx-lm` with `uv tool install mlx-lm`, then start the loopback-only server:

```bash
mlx_lm.server --model mlx-community/granite-3.3-2b-instruct-4bit \
  --host 127.0.0.1 --port 8766 --allowed-origins http://127.0.0.1:8766 \
  --max-tokens 256 --prompt-cache-size 1
```

Plynn prefers Apple Intelligence when available and otherwise contacts only
`127.0.0.1:8766`. If the server is down or a response fails, it uses the
rules-only result. This server does not start automatically after a restart.
On a 16 GB Mac, avoid running other large local model servers concurrently.

## Release engineering

- `make-app.sh` builds with `xcodebuild` and produces a signed .app with SPM resource bundles in `Contents/Resources`.
- `notarize.sh` submits to Apple with `notarytool` and staples the ticket.
- `make-dmg.sh` packages the drag to Applications DMG. Pass `SKIP_BUILD=1` after notarizing so the stapled app is packaged as is.
- `make-release.sh` runs the whole chain and publishes the GitHub release with a signed Sparkle appcast.

## For development

```bash
./scripts/make-app.sh            # build + sign into build/Plynn.app
./scripts/make-app.sh --install  # and replace /Applications/Plynn.app
```

Permissions survive reinstalls because macOS keys them to the bundle ID and the stable Developer ID certificate, not the binary hash.
