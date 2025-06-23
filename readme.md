# Pensieve App — Audio‑capture Proof‑of‑Concept

> **Status : parked**
>
> Development is on hold while the audio‑path issues are investigated. This
> README captures everything that currently works, commands to reproduce the
> tests, observations, and the open problems so it’s easy to pick up again.

---

## 1  Project layout

| Path                        | What it is                                                                                                                                            |
| --------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `mac-helper/`               | Stand‑alone Swift helper built with **ScreenCaptureKit** + **AVFoundation**. Captures a single Chrome tab **+ mic** and writes raw PCM to **stdout**. |
| `native/`                   | Node‑API bridge (`bridge.mm`) that *used* to call ScreenCaptureKit directly. **Deprecated** in favour of the Swift helper.                            |
| `renderer.js`               | Electron renderer – spawns the helper, re‑chunks stdout every *N* ms and sends base‑64 blobs over a WebSocket.                                        |
| `speech_to_text_service.py` | FastAPI handler → decodes b64 → `ffmpeg` → Whisper.                                                                                                   |

---

## 2  Prerequisites

* **macOS 13 Ventura** or newer (ScreenCaptureKit)
* Xcode 15 command‑line tools (for SwiftPM)
* Homebrew `ffmpeg 7.1+` (with `ffplay` for quick listening tests)
* Node 23 + npm, Python 3.11, virtual‑env
* Chrome running with an active *meet.google.com* or YouTube tab

---

## 3  Build & run

```bash
brew install ffmpeg
npm install

cd mac-helper
swift build -c release   # product is .build/release/AudioHelper
cd ..

npm start                  # spawns Electron
```

---

## 4  Low‑level audio tests   🔊

These are **must‑run** before touching the JS side.

**Dry tab only** => ./mac-helper/.build/release/AudioHelper com.google.Chrome --dry-tab | ffmpeg -f f32le -ar 48000 -ac 1 -i - -f wav - | ffplay -

**Dry mic only** => ./mac-helper/.build/release/AudioHelper com.google.Chrome --dry‑mic | ffmpeg -f f32le -ar 48000 -ac 1 -i - -f wav - | ffplay -

**Dry merged** => ./mac-helper/.build/release/AudioHelper com.google.Chrome | ffmpeg -f f32le -ar 48000 -ac 1 -i - -f wav - | ffplay -

> 🔈 Previously, all three produced hiss/garbage — traced to ScreenCaptureKit
> emitting *compressed* audio. Now, after switching to
> `CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer`, audio is **clear**.
>
> ❗ However, **audio chunks repeat** — same buffer is replayed.

---

## 5  Findings so far

* **Audio format** — ScreenCaptureKit does not expose raw LPCM unless we
  extract via `CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer`.
* Using `.pcm` codec in `SCStreamConfiguration` is only available in **macOS 14+**.
* With correct Float32 stereo frames extracted, mono-mix is playable.
* Repetition issue caused by enqueued buffers not being cleared fast enough
  (possibly fed into stdout without dequeue).
* Earlier it appeared clear only because mic was re-recording speaker.

---

## 6  Open problems / TODO

1. **Fix replay issue**

   * Ensure `micBuffers` and `tabBuffers` are correctly dequeued in `.maybeEmit()`
   * Avoid unintentional retain/reuse of buffers

2. **Detect Meet's mic status**

   * JS-side poll for mute/unmute state
   * Or get `chrome.tabCapture.getCapturedTabs()`
   * Dynamically enable/disable mic feed in `AVEngine`

3. **Improve merge**

   * Handle unequal buffer sizes gracefully
   * Optionally include silence padding

4. **Consider virtual mic driver**

   * Ship a HAL plugin that Chrome can select as audio input
   * Guarantees alignment and removes speaker feedback loop

---

## 7  Useful one‑liners

```bash
# Print ASBD from SBs to debug
log stream --predicate 'subsystem == "com.apple.audio"' --info

# Listen to helper output via sox (alternative to ffplay)
./mac-helper/.build/release/AudioHelper com.google.Chrome | sox -t f32 -r 48k -c1 - -d
```

---

## 8. Collaborators
If you're looking into this from my shared repo:

👉 Start by testing the mac-helper output directly with ffplay (section 3)

👉 Reference: QuickRecorder uses a correct sample buffer → AudioBufferList approach
https://github.com/lihaoyun6/QuickRecorder/

Thanks 🙏 — feel free to DM me or open an issue if you debug further!