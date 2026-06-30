// Core state: the recording lifecycle and the language preference.
// Pure logic, unit-tested. No OS calls here.

App_State :: enum u8 {
    IDLE;          // 🎤 not recording
    RECORDING;     // 🔴 capturing audio
    TRANSCRIBING;  // ⏳ uploading + waiting on Groq
}

Language :: enum u8 {
    EN;
    FR;
}

// A hotkey press: idle starts recording, recording stops (→ transcribing).
// A press while transcribing is ignored (returns the same state).
next_state_on_toggle :: (s: App_State) -> App_State {
    if s == {
        case .IDLE;         return .RECORDING;
        case .RECORDING;    return .TRANSCRIBING;
        case .TRANSCRIBING; return .TRANSCRIBING;
    }
    return s;
}

state_icon :: (s: App_State) -> string {
    if s == {
        case .IDLE;         return "🎤";
        case .RECORDING;    return "🔴";
        case .TRANSCRIBING; return "⏳";
    }
    return "🎤";
}

toggle_language :: (l: Language) -> Language {
    if l == .EN return .FR;
    return .EN;
}

lang_code :: (l: Language) -> string {
    if l == .FR return "fr";
    return "en";
}

lang_flag :: (l: Language) -> string {
    if l == .FR return "🇫🇷";
    return "🇺🇸";
}

parse_language :: (s: string) -> Language {
    if trim(s) == "fr" return .FR;
    return .EN;
}
