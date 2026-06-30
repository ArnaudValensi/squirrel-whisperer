# The Squirrel Whisperer (JAI) — Requirements

A native macOS dictation app implemented in JAI. The goals are **speed** (near-instant
start of recording) and **consolidation** (one launchable app that owns the tray icon,
the mic, and the work).

## What the user gets

An app they launch (`SquirrelWhisperer.app`). It:
- shows a **menu-bar (tray) icon** that reflects state: 🎤 idle, 🔴 recording, ⏳ transcribing;
- has a **menu**: toggle language (🇺🇸/🇫🇷), open logs, quit;
- records on a hotkey, transcribes via Groq Whisper, and pastes into the focused app;
- **starts recording the instant the hotkey is pressed** (no per-press process spawn, no
  cold audio device).

## Functional requirements

- **FR1 — Toggle recording.** A resident app registers a native global hotkey; first press
  starts recording, second press stops, transcribes, and pastes. The hotkey is user-settable.
- **FR2 — Paste.** Transcribed text is placed on the clipboard and pasted (⌘V) into the
  focused app.
- **FR3 — Language.** EN/FR selectable from the tray menu; persisted to
  `~/.cache/voice_input_lang`; passed to Whisper as the `language` parameter.
- **FR4 — Tray state.** The menu-bar icon shows idle / recording / transcribing live.
- **FR5 — Logs.** A tray item opens the log file (`~/.cache/voice_input.log`).
- **FR6 — Audible cues.** Start/stop beeps.
- **FR7 — Robust empty handling.** An empty/failed capture logs a clear message, never a
  silent failure or a bogus paste.

## Non-functional requirements

- **NFR1 — Fast start.** Hotkey → capturing in well under ~50 ms. Achieved by keeping the
  audio device **open and warm** for the whole app lifetime and merely un-pausing it.
- **NFR2 — Single artifact.** One `SquirrelWhisperer.app` bundle holds the Microphone + Accessibility
  permissions and contains everything it needs (incl. `libSDL2.dylib`).
- **NFR3 — Testable core.** Pure logic (config parsing, WAV writing, state machine, language
  toggle) is unit-tested; OS/UI/network paths are integration-tested manually.

## Architecture

```
launch SquirrelWhisperer.app  ─▶  resident menu-bar app (LSUIElement)
                            · init Objective-C + AppKit, create NSStatusItem (🎤) + menu
                            · SDL_Init(AUDIO), open output device (beeps)
                            · read GROQ_API_KEY from ~/.config/whisper/config
                            · install Carbon event handler; register the saved hotkey
                            · NSTimer polls a flag set by the hotkey handler

hotkey  ─▶ Carbon handler sets a flag  ─▶ NSTimer tick toggles:
   idle→recording:   open capture device (lazy, stays warm); clear+unpause; icon 🔴; beep
   recording→idle:   pause + close capture (clears mic indicator); icon ⏳; beep;
                     drain queue → encode WAV → Groq (libcurl) → clipboard + CGEvent ⌘V → icon 🎤
```

The transcribe/paste step is deferred one NSTimer tick so the ⏳ icon paints before the
(brief, blocking) upload.

## Components / tools

| Concern | Mechanism |
|---|---|
| Tray icon + menu | AppKit `NSStatusItem`/`NSMenu` via the `Objective_C` module (`objc_msgSend` + `selector()`) |
| App lifecycle / run loop | `NSApplication` (activation policy = Accessory), `NSTimer` |
| Global hotkey | Carbon `RegisterEventHotKey`; recorder captures any combo via a custom `NSView` |
| Mic capture (warm) | `SDL` audio capture: `SDL_OpenAudioDevice(iscapture=1)`, `SDL_DequeueAudio` |
| WAV encode | hand-written canonical 16-bit PCM WAV header + samples |
| Transcription | in-process **libcurl** multipart POST, model `whisper-large-v3`, `response_format=text` |
| Clipboard + paste | `NSPasteboard` + `CGEvent` ⌘V |
| Beeps | `SDL` audio playback (synthesized square-wave motifs) |
| Config | parse `export GROQ_API_KEY="..."` from `~/.config/whisper/config` (or set from the tray) |

## Files

| File | Purpose |
|---|---|
| `~/.config/whisper/config` | `GROQ_API_KEY` |
| `~/.cache/voice_input_lang` | `en`/`fr` |
| `~/.cache/voice_input_hotkey` | saved shortcut (`<keycode> <mods> <label>`) |
| `~/.cache/voice_input.log` | log |

## Source layout

```
build.jai          # metaprogram: build / build-tests / install (+ bundle, codesign, dylibs)
jails.json         # language-server config
src/
  main.jai         # app entry, run loop, state-machine wiring
  config.jai       # read GROQ_API_KEY              (unit-tested)
  wav.jai          # encode PCM → WAV                (unit-tested)
  state.jai        # state machine + language        (unit-tested)
  audio.jai        # SDL warm capture + beeps
  groq.jai         # libcurl transcription
  paste.jai        # NSPasteboard + CGEvent ⌘V
  hotkey.jai       # Carbon global hotkey
  settings.jai     # API-key dialog + shortcut recorder + permissions
  tray.jai         # NSStatusItem + menu + app delegate
  log.jai          # logging to file
  tests.jai        # unit-test entry (MEMORY_DEBUGGER + leak report)
```

## Test strategy

- **Unit (automated, `build-tests`)**: `config` (parse key, missing/quoted/spaced), `wav`
  (header fields + round-trip sample bytes), `state` (transitions, language). Run with the
  memory debugger; the suite reports zero leaks.
- **Integration (manual)**: launch → grant Microphone + Accessibility → press the hotkey →
  confirm capture, Groq text, clipboard set, auto-paste, and negligible start latency.

## Signing

The bundle is code-signed so macOS keeps the Microphone/Accessibility grants. Default is a
local self-signed cert; set `SQUIRREL_SIGN_IDENTITY` to a Developer ID for grants that
persist across rebuilds.
