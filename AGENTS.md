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

- Validate locally with the Swift test suite. Build and publish application
  releases only through GitHub Actions; installed updates arrive through Sparkle.
- Do not build, install, replace, or launch a locally built app, including
  production apps, dev apps, or named dev lanes. Do not run
  `scripts/build_native_app.sh` locally unless Ivan explicitly requests that
  local build or installation. A request to implement, test, commit, push, or
  release does not grant that exception.
- Never bump the installed application's version manually. Select release
  versions through the GitHub release workflow and preserve monotonic Sparkle
  bundle versions.
- Never touch `~/Library/Application Support/Guesli/` during builds or tests.
- Do not reset macOS permissions unless the task explicitly requires it.
- Do not take `CGWindowListCreateImage` screenshots while meeting recording uses
  `SCStream`; doing so interrupts system-audio capture.
- Present `NSSavePanel` with `beginSheetModal(for:)`, never `runModal()`.
- Do not initialize `NSAttributedString(html:)` on the main thread.
- Calendar notifications must use `EKEventStoreChangedNotification` as the
  reliable path; timer polling is fallback-only.

## Tests and releases

Run the full suite with:

```bash
swift test --package-path native/Guesli
```

Build scripts choose a shared SwiftPM scratch directory automatically. Reuse it;
do not create a new multi-gigabyte scratch directory for every retry or share one
scratch directory between simultaneous worktrees.

Before publishing a release, obtain an independent Astra code review of the exact
candidate using the `review-agent` skill and resolve its actionable findings.
Choose the review agent's reasoning effort under the standing delegation rules.

Push the reviewed commit, wait for its successful GitHub CI gate, then dispatch
`.github/workflows/release-macos-app.yml` on that commit's branch with the intended
version. Use the existing workflow to build, sign with `Guesli Dev`, require the
complete LocalVQE runtime, verify hosted assets and Sparkle signatures, publish
the GitHub release, and update the `sparkle-feed` appcast.

Release completion requires the successful workflow for the intended commit,
published downloadable assets, and the expected version, asset URL and signature
in the public Sparkle appcast. Report those separately from proof that a client
actually installed the update. Never replace the local app to simulate delivery.

For notarized releases, staple the app bundle before creating the DMG.
