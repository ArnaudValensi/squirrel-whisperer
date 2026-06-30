// Reads GROQ_API_KEY from ~/.config/whisper/config, which contains a line like:
//   export GROQ_API_KEY="gsk_..."
// The app is launched via Finder/`open`, so it does NOT inherit a shell env —
// hence we parse the config file directly rather than reading getenv.

// Pure parser (unit-tested): pull the value for `key` out of a config blob.
parse_config_value :: (contents: string, key: string) -> (value: string, found: bool) {
    lines := split(contents, "\n");
    defer array_free(lines);  // free the slice array; returned value points into `contents`

    result: string;
    found := false;
    for line : lines {
        l := trim(line);
        if l.count == 0 || l[0] == #char "#" continue;

        // strip optional leading "export "
        if begins_with(l, "export ") l = trim(slice(l, 7, l.count - 7));

        eq := find_index_from_left(l, #char "=");
        if eq < 0 continue;

        name := trim(slice(l, 0, eq));
        if name != key continue;

        result = trim_quotes(trim(slice(l, eq + 1, l.count - (eq + 1))));
        found = true;
        break;
    }
    return result, found;
}

trim_quotes :: (s: string) -> string {
    r := s;
    if r.count >= 2 && (r[0] == #char "\"" || r[0] == #char "'") && r[r.count-1] == r[0] {
        r = slice(r, 1, r.count - 2);
    }
    return r;
}

// File-backed wrapper (integration; not unit-tested).
read_groq_api_key :: () -> (key: string, ok: bool) {
    path := tprint("%/.config/whisper/config", home_dir());
    contents, ok := read_entire_file(path);
    if !ok return "", false;
    defer free(contents);
    v, found := parse_config_value(contents, "GROQ_API_KEY");
    if !found return "", false;
    return copy_string(v), true;  // copy out before the file buffer is freed
}

home_dir :: () -> string {
    h := c_getenv(temp_c_string("HOME"));
    if h return to_string(h);
    return "/tmp";
}

#scope_file
LibC_for_env :: #system_library "libc";
c_getenv :: (name: *u8) -> *u8 #foreign LibC_for_env "getenv";
#scope_export
