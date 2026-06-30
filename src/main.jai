#import "Basic"()(MEMORY_DEBUGGER=IS_DEV);  // IS_DEV is injected by build.jai
#import "String";
#import "File";
#import "File_Utilities";
#import "Math";
#import "Process";
#import "Thread";
SDL :: #import "SDL";
#import "Curl";
#import "Objective_C";
#import "Objective_C/AppKit";

#load "arena.jai";
#load "config.jai";
#load "wav.jai";
#load "state.jai";
#load "log.jai";
#load "audio.jai";
#load "groq.jai";
#load "paste.jai";
#load "hotkey.jai";
#load "settings.jai";
#load "tray.jai";

// --- global app state ------------------------------------------------------

g_state:   App_State = .IDLE;
g_lang:    Language  = .EN;
g_api_key: string;
g_have_key: bool;

g_status_item:    *void;
g_lang_menu_item: *void;
g_delegate:       *void;

g_toggle_pending: bool;  // set by the hotkey handler, consumed on the run loop

TMP_WAV :: "/tmp/voiceinput.wav";

// Transcription runs on a background thread so the tray stays responsive during
// the upload. Inputs (the WAV path, API key, language) are read straight from
// globals/constants by the worker; only the result crosses back. The main-thread
// timer notices the thread finished (thread_is_done) and consumes it (paste + UI).
// Only one runs at a time (TRANSCRIBING blocks new toggles), so one thread suffices.
g_transcript:     string;  // worker output (heap); freed by the main thread on consume
g_transcript_ok:  bool;
g_worker:         Thread;
g_worker_active:  bool;     // main-thread only

// --- entry -----------------------------------------------------------------

main :: () {
    args := get_command_line_arguments();
    #if IS_DEV  this_allocation_is_not_a_leak(args.data);  // one-time, lives for the whole run

    if args.count >= 2 && args[1] == "--record-test" {
        secs := ifx args.count >= 3 then string_to_float(args[2]) else 2.0;
        if audio_init() {
            audio_start();
            SDL.SDL_Delay(xx (secs * 1000));
            wav, n := audio_stop_and_encode();
            write_entire_file("/tmp/voiceinput_test.wav", to_string(wav.data, wav.count));
            log_line(tprint("captured % bytes", n));
            array_free(wav);
        }
        return;
    }
    if args.count >= 3 && args[1] == "--transcribe-test" {
        key, ok := read_groq_api_key();
        if !ok { log_line("no api key"); return; }
        t, tok := transcribe(args[2], key, "en");
        log_line(ifx tok then tprint("transcript: %", t) else "failed");
        return;
    }

    run_app();
}

run_app :: () {
    init_objective_c();
    init_app_kit();
    pool := objc_init(objc_alloc(NSAutoreleasePool));

    g_api_key, g_have_key = read_groq_api_key();
    if !g_have_key  log_line("No GROQ_API_KEY yet — set it from the tray menu");
    g_lang = load_lang();
    load_hotkey();

    // Prompt-free audio setup at startup; the capture device (which triggers the
    // mic prompt) is opened lazily on the first recording and stays warm after.
    audio_sdl_init();
    audio_play_init();

    app := NSApplication.sharedApplication();
    NSApplication.setActivationPolicy(app, NSApplicationActivationPolicyAccessory);
    install_edit_menu(app);   // Cmd+C/V/X/A in text fields (e.g. the API key dialog)

    g_delegate = register_delegate();
    g_status_item = create_status_item();
    build_menu(g_status_item, g_delegate);
    update_icon();

    install_hotkey_handler();
    apply_current_hotkey();
    NSTimer.scheduledTimerWithTimeInterval(0.03, g_delegate, selector("onTimer:"), null, YES);

    log_line(tprint("The Squirrel Whisperer started (% to toggle)", g_hotkey_label));
    NSApplication.run(app);
}

// --- run-loop tick: drive the state machine off the hotkey flag ------------

app_on_timer :: () {
    temp_scope();
    if g_toggle_pending {
        g_toggle_pending = false;
        handle_toggle();
    } else if g_worker_active && thread_is_done(*g_worker) {
        finish_transcription();
    }
}

handle_toggle :: () {
    if g_state == {
        case .IDLE;
            audio_start();
            g_state = .RECORDING;
            update_icon();
            audio_beep(true);

        case .RECORDING;
            audio_beep(false);
            wav, sample_bytes := audio_stop_and_encode();
            defer array_free(wav);
            write_entire_file(TMP_WAV, to_string(wav.data, wav.count));

            if sample_bytes < 1000 {
                log_line("recording was empty");
                g_state = .IDLE;
                update_icon();
            } else if !g_have_key {
                log_line("no API key; cannot transcribe");
                g_state = .IDLE;
                update_icon();
            } else {
                start_transcription();           // background thread; main loop stays responsive
                g_state = .TRANSCRIBING;
                update_icon();                   // ⏳ paints (we don't block)
            }

        case .TRANSCRIBING;
            // ignore toggles while busy
    }
}

// --- async transcription ---------------------------------------------------

start_transcription :: () {
    g_transcript    = "";
    g_transcript_ok = false;

    g_worker = .{};  // fresh struct; thread_init does not clear a reused one (is_done etc.)
    thread_init(*g_worker, transcribe_worker);
    thread_start(*g_worker);
    g_worker_active = true;
}

transcribe_worker :: (t: *Thread) -> s64 {
    context.allocator = context.default_allocator;  // result must outlive the thread (heap, not temp)
    g_transcript, g_transcript_ok = transcribe(TMP_WAV, g_api_key, lang_code(g_lang));
    return 0;  // the trampoline sets thread_is_done after this; the timer then consumes
}

finish_transcription :: () {
    g_worker_active = false;
    thread_deinit(*g_worker);  // worker has returned; this joins/cleans up

    if g_transcript_ok && g_transcript.count > 0 {
        paste_to_focused_app(g_transcript);
        log_line(tprint("pasted (% chars)", g_transcript.count));  // length only, not the text
    } else {
        log_line("no text transcribed");
    }

    if g_transcript.data  free(g_transcript.data,, context.default_allocator);
    g_transcript = "";

    g_state = .IDLE;
    update_icon();
}

update_icon :: () {
    set_status_title(g_status_item, state_icon(g_state));
}

// --- menu actions ----------------------------------------------------------

app_toggle_language :: () {
    temp_scope();
    g_lang = toggle_language(g_lang);
    save_lang(g_lang);
    send_p(g_lang_menu_item, selector("setTitle:"), nss(lang_menu_title()));
    log_line(tprint("language: %", lang_code(g_lang)));
}

app_open_logs :: () {
    temp_scope();
    run_command("open", log_path());
}

app_quit :: () {
    temp_scope();
    log_leaks("app stop");
    exit(0);
}

lang_menu_title :: () -> string {
    return tprint("Language: %", lang_flag(g_lang));
}

// --- leak diagnostics ------------------------------------------------------
// When DIAG_LEAKS is on, the app writes one memory-leak report to
// ~/.cache/voice_input.log when it stops (Jai heap allocations only; temporary
// storage and Objective-C objects are separate allocators, not tracked here).

DIAG_LEAKS :: IS_DEV;

log_leaks :: (tag: string) {
    #if DIAG_LEAKS {
        builder: String_Builder;
        ctx := context;
        ctx.logger      = leak_sink;
        ctx.logger_data = *builder;
        push_context ctx {
            report_memory_leaks();
        }
        report := builder_to_string(*builder);
        defer free(report);  // don't let the diagnostic leak its own output

        file, ok := file_open(log_path(), for_writing=true, keep_existing_content=true);
        if ok {
            file_seek(file, 0, .END);
            file_write(*file, tprint("\n===== leak report: % =====\n", tag));
            file_write(*file, report);
            file_close(*file);
        }
    }
}

leak_sink :: (message: string, data: *void, info: Log_Info) {
    b := cast(*String_Builder) data;
    append(b, message);
}

// --- language persistence --------------------------------------------------

lang_file :: () -> string {
    return tprint("%/.cache/voice_input_lang", home_dir());
}

load_lang :: () -> Language {
    contents, ok := read_entire_file(lang_file());
    if !ok return .EN;
    defer free(contents);
    return parse_language(contents);
}

save_lang :: (l: Language) {
    make_directory_if_it_does_not_exist(tprint("%/.cache", home_dir()), recursive=true);
    write_entire_file(lang_file(), lang_code(l));
}
