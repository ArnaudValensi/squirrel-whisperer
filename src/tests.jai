// Unit-test entry point. Built via `jai build.jai - build-tests` → ./build/tests
#import "Basic"()(MEMORY_DEBUGGER=true);
#import "Print_Color";
#import "String";
#import "File";
Wav_File :: #import "Wav_File";

#load "config.jai";
#load "wav.jai";
#load "state.jai";

failures := 0;

main :: () {
    print("\n");
    test("config", test_config);
    test("wav",    test_wav);
    test("state",  test_state);

    if failures == 0 {
        print_color("\nAll tests passed.\n", color = .GREEN);
    } else {
        print_color(tprint("\n% test(s) FAILED.\n", failures), color = .RED);
        exit(1);
    }

    report_memory_leaks();
}

test_config :: () {
    {
        v, ok := parse_config_value("export GROQ_API_KEY=\"gsk_abc123\"\n", "GROQ_API_KEY");
        check(ok, "found key with export + quotes");
        check(v == "gsk_abc123", tprint("value parsed (%)", v));
    }
    {
        v, ok := parse_config_value("GROQ_API_KEY=plain\n", "GROQ_API_KEY");
        check(ok && v == "plain", "found key without export/quotes");
    }
    {
        v, ok := parse_config_value("# a comment\nOTHER=1\n", "GROQ_API_KEY");
        check(!ok, "missing key reports not found");
    }
    {
        v, ok := parse_config_value("  export   GROQ_API_KEY = 'spaced'  \n", "GROQ_API_KEY");
        check(ok && v == "spaced", tprint("tolerates spaces + single quotes (%)", v));
    }
}

test_wav :: () {
    // 4 samples of s16 mono = 8 bytes of PCM.
    pcm := u8.[ 0x01,0x02, 0x03,0x04, 0xff,0x7f, 0x00,0x80 ];
    wav := encode_wav(pcm, 16000, 1, 16);
    defer array_free(wav);

    check(wav.count == 44 + pcm.count, tprint("total size 44+data (%)", wav.count));

    s := to_string(wav.data, wav.count);
    fmt, samples, ok := Wav_File.get_wav_header(s);
    check(ok, "Wav_File parses our header");
    check(fmt.wFormatTag == 1, "format tag = PCM");
    check(fmt.nChannels == 1, "channels = 1");
    check(fmt.nSamplesPerSec == 16000, tprint("sample rate (%)", fmt.nSamplesPerSec));
    check(fmt.wBitsPerSample == 16, "bits = 16");

    // sample payload round-trips byte-for-byte
    same := samples.count == pcm.count;
    if same  for 0..pcm.count-1  if samples[it] != pcm[it] { same = false; break; }
    check(same, "PCM payload round-trips");
}

test_state :: () {
    check(next_state_on_toggle(.IDLE)        == .RECORDING,    "idle -> recording");
    check(next_state_on_toggle(.RECORDING)   == .TRANSCRIBING, "recording -> transcribing");
    check(next_state_on_toggle(.TRANSCRIBING)== .TRANSCRIBING, "transcribing ignores toggle");

    check(state_icon(.IDLE) == "🎤" && state_icon(.RECORDING) == "🔴" && state_icon(.TRANSCRIBING) == "⏳", "icons map");

    check(toggle_language(.EN) == .FR && toggle_language(.FR) == .EN, "language toggles");
    check(lang_code(.EN) == "en" && lang_code(.FR) == "fr", "lang codes");
    check(parse_language("fr") == .FR && parse_language("en\n") == .EN && parse_language("") == .EN, "parse language (default en)");
}

// --- tiny test harness ---------------------------------------------------

test :: (name: string, fn: () -> ()) {
    print_color(tprint("Testing  %\n", name), color = .MAGENTA);
    fn();
}

check :: (cond: bool, msg: string) {
    if cond {
        print("  ok   %\n", msg);
    } else {
        failures += 1;
        print_color(tprint("  FAIL %\n", msg), color = .RED);
    }
}
