# Guesli CLI Contract

## Commands

- `guesli-cli spec`
- `guesli-cli info`
- `guesli-cli transcribe <file> [--format text|json|markdown] [--model MODEL] [--summarize] [--save-meeting] [--title TITLE] [--output PATH] [--dictionary PATH] [--emit-partials PATH]`
- `guesli-cli meetings list [--limit N] [--folder-id ID]`
- `guesli-cli meetings get <id>`
- `guesli-cli meetings update-notes <id> (--stdin | --file <path>)`
- `guesli-cli dictations list [--limit N]`
- `guesli-cli dictations get <id>`

## Output shape

Data commands return JSON to stdout. `transcribe` returns plain transcript text by default, `--format markdown` emits markdown text with title, optional summary, and raw transcript sections, and `--format json` uses the same success envelope.

Success envelope:
```json
{
  "ok": true,
  "command": "guesli-cli meetings get",
  "data": {},
  "meta": {
    "schemaVersion": 1,
    "generatedAt": "2026-03-17T00:00:00Z",
    "dbPath": "/Users/example/Library/Application Support/Guesli/guesli.db",
    "warnings": []
  }
}
```

Failure envelope:
```json
{
  "ok": false,
  "command": "guesli-cli meetings get 999",
  "error": {
    "code": "not_found",
    "message": "No meeting exists with id 999.",
    "fix": "Run `guesli-cli meetings list` to find a valid ID."
  },
  "meta": {
    "schemaVersion": 1,
    "generatedAt": "2026-03-17T00:00:00Z",
    "dbPath": "",
    "warnings": []
  }
}
```

## Important fields

Meeting list rows include:
- `id`
- `title`
- `startTime`
- `durationSeconds`
- `wordCount`
- `folderID`
- `notesState`

Meeting details also include:
- `rawTranscript`
- `formattedNotes`
- `calendarEventID`
- `micAudioPath`
- `systemAudioPath`

`notesState` values:
- `missing`
- `raw_transcript_fallback`
- `structured_notes`

Dictation details include:
- `rawText`
- `appContext`
- `timestamp`
- `durationSeconds`

Transcribe JSON data includes:
- `transcript`
- `summary`
- `durationSeconds`
- `wordCount`
- `model`
- `warnings`
- `savedMeetingID`
- `title`

Supported transcribe inputs:
- `.mp3`
- `.mp4`
- `.m4a`
- `.wav`

Supported transcribe models are listed by `guesli-cli transcribe --help`; `gigaam-onnx` is the default. `--emit-partials` is available only with `parakeet-eou-320ms`.

Transcribe behavior:
- progress and model logs go to stderr
- default stdout is transcript text only
- `--format json` includes warnings in both `data.warnings` and `meta.warnings`
- `--summarize` preserves the transcript if summary generation fails and returns a warning
- `--summarize` reuses the app's configured summary backend, including its ChatGPT session when available
- `--save-meeting` stores the meeting as `source = audio_import`
- `--output <path>` writes the selected output format to a file and keeps stdout clean

## Expected agent pattern

- `transcribe <file>` for raw local transcription
- `transcribe <file> --format json` when structured metadata is needed
- `transcribe <file> --save-meeting` when the imported audio should appear in Guesli
- `list` to discover IDs
- `get` to fetch full text
- external summarize/analyze in the coding agent
- `update-notes` to write notes back
