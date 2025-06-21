# Pensieve App — Audio‑capture Proof‑of‑Concept

> **Status : parked (2025‑06‑21)**
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
# 1⃣ Install JS deps & build Electron bits
npm install
npm run rebuild-native   # still needed for the Node‑API shim (optional)

# 2⃣ Build Swift helper (Release)
cd mac-helper
swift build -c release   # product is .build/release/AudioHelper
cd ..

# 3⃣ Start backend (FastAPI) in a venv
uvicorn main:app --reload   # not committed, local only

# 4⃣ Run the desktop UI
npm start                  # spawns Electron
```

---

## 4  Low‑level audio tests   🔊

These are **must‑run** before touching the JS side.

| Test             | Command                                             |                                               |            |
| ---------------- | --------------------------------------------------- | --------------------------------------------- | ---------- |
| **Dry tab only** | `./AudioHelper com.google.Chrome --dry‑tab \`<br>\` | ffplay -f f32le -ar 48000 -ac 1 -\`           |            |
| **Dry mic only** | `./AudioHelper com.google.Chrome --dry‑mic \`<br>\` | ffplay -f f32le -ar 48000 -ac 1 -\`           |            |
| **Dry merged**   | `./AudioHelper com.google.Chrome \`<br>\`           | ffmpeg -f f32le -ar 48000 -ac 1 -i - -f wav - | ffplay -\` |

./AudioHelper com.google.Chrome --dry-mic | ffmpeg -f s16le -ar 48000 -ac 2 -i - -f wav - | ffplay - ==> only tab audio
./AudioHelper com.google.Chrome --dry-tab | ffmpeg -f f32le -ar 48000 -ac 1 -i - -f wav - | ffplay - ==> only mic audio

> \:warning: At the moment all three commands play *white‑noise like garbage* →
> proves the helper is emitting the **wrong format** (see §5).

---

## 5  Findings so far

* **ScreenCaptureKit format** — without `cfg.audioCodec = .pcm` (macOS 14+) the
  buffer we pull via `CMSampleBufferGetDataBuffer` is *not* raw Float‑32 PCM –
  likely AAC. Treating those bytes as floats ⇒ hiss.
* **Correct way** is to fetch the `AudioBufferList` from the `CMSampleBuffer`
  (QuickRecorder does this).
* **Merging path** – current `AVEngine` converts mic/tap to Float‑32 mono and
  mixes 50/50, but still uses the bad tab bytes → distorted output.
* **Backend** – when fed a *good* 48 kHz f32le mono file Whisper works fine.

---

## 6  Open problems / TODO

1. **Fix helper delegate**

   * Use `CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer` and inspect
     the ASBD. Confirm format is `lpcm`, 32‑bit float, **non‑interleaved**.
2. **Force PCM in config** (macOS 14):

   ```swift
   if #available(macOS 14.0, *) {
       cfg.audioCodec = .pcm
       cfg.audioChannelCount = 1
   }
   ```
3. **Verify with ffplay** – repeat the three dry tests until they sound clean.
4. **Re‑enable Electron pipeline** – once stdout is correct, the renderer’s
   base‑64 chunks should decode to valid wave and Whisper will align.
5. **Echo / local monitoring** – optional: expose a gain slider; default to 0.

---

## 7  Useful one‑liners

```bash
# Print ASBD from SBs to debug
log stream --predicate 'subsystem == "com.apple.audio"' --info

# Listen to helper output via sox (alternative to ffplay)
./AudioHelper com.google.Chrome | sox -t f32 -r 48k -c1 - -d
```

---

## 8  Parking notice

Development paused **2025‑06‑21** after confirming that ScreenCaptureKit is
feeding compressed data. Next session should start with *Step 1* in **Open
problems** above.

Happy hacking — see you later!
*— A.*
