// Microphone capture via SDL, kept warm for instant start.
//
// The device is opened once at startup with a null callback, so SDL queues
// captured samples internally. Starting = clear queue + un-pause (instant).
// Stopping = pause + drain the queue into a buffer we wrap as a WAV.
//
// SDL is imported namespaced (SDL.) because it exports a `NO` symbol that
// collides with Objective-C's BOOL `NO`.

AUDIO_SAMPLE_RATE :: 16000;
AUDIO_CHANNELS    :: 1;
AUDIO_BITS        :: 16;

g_audio_dev: SDL.SDL_AudioDeviceID;
g_sdl_inited: bool;

// SDL audio subsystem init (no mic permission needed).
audio_sdl_init :: () -> bool {
    if g_sdl_inited return true;
    if SDL.SDL_Init(SDL.SDL_INIT_AUDIO) != 0 {
        log_line(tprint("SDL_Init failed: %", to_string(SDL.SDL_GetError())));
        return false;
    }
    g_sdl_inited = true;
    return true;
}

// Open the capture device (triggers the macOS mic prompt on first use).
audio_open_capture :: () -> bool {
    if g_audio_dev != 0 return true;
    if !audio_sdl_init() return false;

    want: SDL.SDL_AudioSpec;
    want.freq     = AUDIO_SAMPLE_RATE;
    want.format   = SDL.AUDIO_S16;
    want.channels = AUDIO_CHANNELS;
    want.samples  = 1024;
    want.callback = null;        // null callback => use the audio queue API

    have: SDL.SDL_AudioSpec;
    g_audio_dev = SDL.SDL_OpenAudioDevice(null, 1, *want, *have, 0);  // iscapture = 1
    if g_audio_dev == 0 {
        log_line(tprint("SDL_OpenAudioDevice failed: %", to_string(SDL.SDL_GetError())));
        return false;
    }
    return true;
}

// Convenience for the CLI test path: full init incl. capture.
audio_init :: () -> bool {
    return audio_open_capture();
}

audio_start :: () {
    if !audio_open_capture() return;
    SDL.SDL_ClearQueuedAudio(g_audio_dev);
    SDL.SDL_PauseAudioDevice(g_audio_dev, 0);
}

// Stop capturing and return the recording as encoded WAV bytes (caller frees).
// We CLOSE the device (not just pause) so macOS clears the "mic in use" indicator;
// it's reopened on the next recording.
audio_stop_and_encode :: () -> (wav: [] u8, sample_bytes: int) {
    if g_audio_dev == 0  return .[], 0;
    SDL.SDL_PauseAudioDevice(g_audio_dev, 1);

    size := SDL.SDL_GetQueuedAudioSize(g_audio_dev);
    pcm := NewArray(xx size, u8);
    defer array_free(pcm);
    if size > 0 {
        got := SDL.SDL_DequeueAudio(g_audio_dev, pcm.data, size);
        pcm.count = xx got;
    }

    SDL.SDL_CloseAudioDevice(g_audio_dev);
    g_audio_dev = 0;

    wav := encode_wav(pcm, AUDIO_SAMPLE_RATE, AUDIO_CHANNELS, AUDIO_BITS);
    return wav, pcm.count;
}

// --- beeps (SDL playback) -------------------------------------------------
// A second SDL device for output, kept open. We synthesize two short
// chiptune motifs once (rising = start, falling = stop) and queue them.

g_play_dev: SDL.SDL_AudioDeviceID;
g_beep_start: [] s16;
g_beep_stop:  [] s16;

audio_play_init :: () {
    if !audio_sdl_init() return;
    want: SDL.SDL_AudioSpec;
    want.freq     = AUDIO_SAMPLE_RATE;
    want.format   = SDL.AUDIO_S16;
    want.channels = AUDIO_CHANNELS;
    want.samples  = 1024;
    want.callback = null;

    have: SDL.SDL_AudioSpec;
    g_play_dev = SDL.SDL_OpenAudioDevice(null, 0, *want, *have, 0);  // iscapture = 0
    if g_play_dev == 0 {
        log_line(tprint("SDL play device failed: %", to_string(SDL.SDL_GetError())));
        return;
    }
    g_beep_start = synth_motif(523, 784);  // C5 -> G5
    g_beep_stop  = synth_motif(784, 523);  // G5 -> C5
    SDL.SDL_PauseAudioDevice(g_play_dev, 0);   // unpaused; plays whatever we queue
}

audio_beep :: (rising: bool) {
    if g_play_dev == 0 return;
    tone := ifx rising then g_beep_start else g_beep_stop;
    if tone.count == 0 return;
    SDL.SDL_ClearQueuedAudio(g_play_dev);
    SDL.SDL_QueueAudio(g_play_dev, tone.data, xx (tone.count * size_of(s16)));
}

// Two square-wave notes with a short decay envelope.
synth_motif :: (freq_a: float, freq_b: float) -> [] s16 {
    note_dur :: 0.07;
    rate := cast(float) AUDIO_SAMPLE_RATE;
    n := cast(int)(rate * note_dur);
    amp :: 6000.0;

    out := NewArray(2 * n, s16);
    freqs := float.[ freq_a, freq_b ];
    idx := 0;
    for f : freqs {
        for i : 0..n-1 {
            t := i / rate;
            phase := (f * t) - floor(f * t);   // 0..1
            sq := ifx phase < 0.5 then 1.0 else -1.0;
            env := exp(-t / (note_dur * 0.5));
            out[idx] = cast(s16)(amp * env * sq);
            idx += 1;
        }
    }
    return out;
}
