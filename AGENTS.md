# GooseLee agent guide

GooseLee is an independent downstream product. Do not restore removed upstream
features or merge upstream wholesale. Port individual fixes only when they fit
GooseLee's meeting-first, Russian-first scope.

## Product boundaries

- Keep the primary ASR catalog limited to GigaAM v3, Parakeet v3, and Nemotron
  3.5 Multilingual.
- Parakeet Realtime EOU is an optional English-only live meeting preview. It is
  never downloaded automatically and never replaces the final transcript.
- Keep Qwen transcript cleanup.
- Prefer local processing, explicit settings, and a small reliable feature set.
- Do not add telemetry, donation prompts, paid upsells, or user-content logging.

## Development safety

- Use `./scripts/dev-test.sh` for local development. Named lanes `A`, `B`, and
  `C` exist only when isolated app identities are needed.
- Never touch `~/Library/Application Support/Guesli/` during builds or tests.
- Do not reset macOS permissions unless the task explicitly requires it.
- Do not take `CGWindowListCreateImage` screenshots while meeting recording uses
  `SCStream`; doing so interrupts system-audio capture.
- Present `NSSavePanel` with `beginSheetModal(for:)`, never `runModal()`.
- Do not initialize `NSAttributedString(html:)` on the main thread.
- Calendar notifications must use `EKEventStoreChangedNotification` as the
  reliable path; timer polling is fallback-only.

## Tests and builds

Run the full suite with:

```bash
swift test --package-path native/Guesli
```

Build scripts choose a shared SwiftPM scratch directory automatically. Reuse it;
do not create a new multi-gigabyte scratch directory for every retry or share one
scratch directory between simultaneous worktrees.

The maintainer machine has no Apple Developer ID certificate. Its canonical
local production build is:

```bash
GUESLI_SKIP_SIGN=1 GUESLI_SIGN_IDENTITY="Guesli Dev" ./scripts/build_native_app.sh
```

Both variables are required. The stable self-signed identity preserves macOS
TCC grants; ad-hoc signing can silently reset Accessibility, Input Monitoring,
Screen Recording, and Microphone permissions.

A production build is complete only after verifying the installed app has
`Authority=Guesli Dev`, passes `codesign --verify --deep --strict`, runs under a
fresh PID started after the binary modification time, and reports the expected
version from `Info.plist`.

For notarized releases, staple the app bundle before creating the DMG.
