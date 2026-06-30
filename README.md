<p align="center">
  <img src="assets/banner.png" alt="The Squirrel Whisperer" width="100%">
</p>

# The Squirrel Whisperer

The Squirrel Whisperer is a small, open source menu bar app for macOS that turns your voice
into text anywhere. Press a shortcut, talk, press it again, and what you said is typed straight
into the app you are using. It is probably one of the fastest dictation apps around: written in Jai and
carefully engineered, it starts recording the instant you press the key, with no app to wake
up and no lag. Transcription runs on the Groq Whisper API and comes back in a fraction of a
second.

It also translates as it goes: speak in any language and your words are transcribed and
translated into the language you select.

## Install

1. Download the latest release and drag The Squirrel Whisperer into your Applications folder.
   (Builds will be published on the Releases page.)
2. Launch it. A microphone icon appears in your menu bar.
3. Click the icon, choose **Set Groq API Key**, and paste your key. You can get a free key at
   [console.groq.com](https://console.groq.com).
4. The first time you record, macOS asks for two permissions: **Microphone** (so it can hear
   you) and **Accessibility** (so it can paste for you). Allow both.
5. You are ready. The default shortcut is **Control + backtick**, and you can change it any
   time from the **Shortcut** menu.

## How to use it

- Press the shortcut to start recording, speak, then press it again. The text is pasted where
  your cursor is.
- The menu bar icon shows what is happening: idle, recording, or transcribing.
- The menu lets you switch language (English or French), change the shortcut, update your key,
  and open the logs.

## Built with Jai

The Squirrel Whisperer is written in [Jai](https://en.wikipedia.org/wiki/Jai_%28programming_language%29),
a high performance systems programming language created by
[Jonathan Blow](https://en.wikipedia.org/wiki/Jonathan_Blow), designer of
[The Witness](http://the-witness.net) and the upcoming
[Order of the Sinking Star](https://store.steampowered.com/app/499170/Order_of_the_Sinking_Star/)
(which is itself built in Jai). Jai's speed and low overhead are a big part of why this app
feels instant.

## For developers

Build instructions are in [DEVELOPING.md](DEVELOPING.md), and the design is described in
[REQUIREMENTS.md](REQUIREMENTS.md).
