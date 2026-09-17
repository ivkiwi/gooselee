# GooseLee Meet Speaker Bridge

Unpacked Chromium extension for local testing.

1. Open `chrome://extensions`.
2. Enable Developer mode.
3. Load unpacked: `browser-extension/guesli-meet-speaker`.
4. In GooseLee, open **Settings → Meetings → Advanced**, enable the Google Meet speaker bridge, and copy its pairing token.
5. Open the extension's **Details → Extension options**, paste the token, and save it.
6. Join Google Meet and start a GooseLee meeting recording.

After updating the extension files, click **Reload** on `chrome://extensions` and reload the Meet tab so Chromium installs the new manifest and content scripts.

The extension sends only active speaker name samples, visible Meet participant names, and the current Meet URL to `http://127.0.0.1:1477/v1/meet-speaker`.
GooseLee accepts authenticated requests only while it is recording the matching active Google Meet.
It enables Meet captions locally once per call and uses only recent caption rows tied to a known participant; it does not scan arbitrary page text for speaker names.
