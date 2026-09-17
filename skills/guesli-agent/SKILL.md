---
name: guesli-agent
description: Use when working with local Guesli meetings, notes, dictations, audio-file transcription, or raw transcripts through the bundled `guesli-cli` CLI. Prefer this skill when a coding agent needs to transcribe local audio, inspect transcripts, summarize meetings with its own model, or write notes back into Guesli without requiring the user's API keys.
---

# Guesli Agent

Use the local `guesli-cli` CLI as the source of truth for meeting and dictation data.

## CLI discovery

Resolve the binary in this order:
1. `command -v guesli-cli`
2. `command -v guesli` only when the resolved path is a Homebrew cask alias to `Guesli.app/Contents/MacOS/guesli-cli`; verify with `guesli info`
3. `/Applications/Guesli.app/Contents/MacOS/guesli-cli`
4. A local SwiftPM build path inside this repo

If discovery is uncertain, run the candidate binary with `info` first and reject unrelated `guesli` executables.

## Core workflow

1. Inspect capabilities with `guesli-cli spec` if you do not know the exact subcommand shape.
2. To transcribe a local audio file, run `guesli-cli transcribe <file>` and read plain transcript text from stdout.
3. Use `guesli-cli transcribe <file> --format json` when you need duration, word count, model, warnings, summary, or saved meeting ID.
4. Add `--save-meeting` to persist an imported meeting with `source = audio_import`.
5. List candidate meetings with `guesli-cli meetings list --limit 10`.
6. Fetch a full record with `guesli-cli meetings get <id>`.
7. Use the coding agent's own model to analyze `rawTranscript` and `formattedNotes`.
8. If you want to persist improved notes, write markdown back with:
   - `cat notes.md | guesli-cli meetings update-notes <id> --stdin`
   - or `guesli-cli meetings update-notes <id> --file notes.md`

## Rules

- Treat CLI stdout as the API. Data commands are JSON by default; `transcribe` is plain text by default, Markdown with `--format markdown`, and JSON with `--format json`.
- Treat stderr as informational only.
- Do not mutate `rawTranscript`; only update `formattedNotes`.
- Prefer the meeting transcript when `notesState` is `missing` or `raw_transcript_fallback`.
- Use `--db-path` or `--support-dir` only when the default Guesli data location is wrong.

## When to read references

Read `references/cli-contract.md` if you need the exact command tree, field definitions, or failure behavior.
