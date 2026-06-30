// Settings: store the Groq API key, and record an arbitrary global shortcut.
//
// The shortcut recorder is a small window whose content view is a custom NSView
// subclass overriding keyDown:/performKeyEquivalent: — it captures the next combo
// (keyCode + modifiers), validates it, and registers it via Carbon. NSEvent's
// keyCode is the same virtual code Carbon uses, so only the modifier bits are remapped.

// --- current shortcut state ------------------------------------------------

DEFAULT_KEYCODE :: 50;            // backtick `
DEFAULT_MODS    :: MOD_CONTROL;
DEFAULT_LABEL   :: "⌃`";

g_hotkey_keycode: u32 = DEFAULT_KEYCODE;
g_hotkey_mods:    u32 = DEFAULT_MODS;
g_hotkey_label:   string;   // set on the persistent allocator by load_hotkey at startup

g_shortcut_parent_item: *void;   // the "Shortcut: …" menu item (title updated on change)
g_recorder_window:      *void;
g_recorder_class:       Class;

apply_current_hotkey :: () {
    set_hotkey(g_hotkey_keycode, g_hotkey_mods);
}

shortcut_menu_title :: () -> string {
    return tprint("Shortcut: %", g_hotkey_label);
}

update_shortcut_menu_title :: () {
    if g_shortcut_parent_item  send_p(g_shortcut_parent_item, selector("setTitle:"), nss(shortcut_menu_title()));
}

build_shortcut_submenu :: (target: *void) -> *void {
    menu := send(objc_alloc(objc_getClass("NSMenu")), selector("init"));
    add_menu_item(menu, "Set Shortcut…",    "recordShortcut:", target);
    add_menu_item(menu, "Reset to Default", "resetShortcut:",  target);
    return menu;
}

app_reset_shortcut :: () {
    temp_scope();
    g_hotkey_keycode = DEFAULT_KEYCODE;
    g_hotkey_mods    = DEFAULT_MODS;
    set_persistent_string(*g_hotkey_label, DEFAULT_LABEL);
    apply_current_hotkey();
    save_hotkey();
    update_shortcut_menu_title();
    log_line("shortcut reset to default (⌃`)");
}

// --- recorder --------------------------------------------------------------

Recorder_View :: struct {
    using #as view: NSView;

    acceptsFirstResponder :: (self: *Recorder_View, _sel: Selector) -> BOOL #c_call {
        return 1;
    } @selector(acceptsFirstResponder)

    keyDown :: (self: *Recorder_View, _sel: Selector, event: id) #c_call {
        push_context { recorder_capture(event); }
    } @selector(keyDown:)

    performKeyEquivalent :: (self: *Recorder_View, _sel: Selector, event: id) -> BOOL #c_call {
        handled := false;
        push_context { handled = recorder_capture(event); }
        return ifx handled then cast(BOOL) 1 else cast(BOOL) 0;
    } @selector(performKeyEquivalent:)
}

register_recorder_class :: () {
    if g_recorder_class != null return;
    c := objc_create_class(Recorder_View, NSView);
    objc_add_instance_method(c, Recorder_View.acceptsFirstResponder, "acceptsFirstResponder");
    objc_add_instance_method(c, Recorder_View.keyDown,               "keyDown:");
    objc_add_instance_method(c, Recorder_View.performKeyEquivalent,  "performKeyEquivalent:");
    objc_finalize_class(c);
    g_recorder_class = c;
}

app_record_shortcut :: () {
    temp_scope();
    register_recorder_class();

    win := objc_alloc(objc_getClass("NSWindow"));
    fw : (*void, Selector, NSRect, u64, u64, BOOL) -> *void #c_call = xx objc_msgSend;
    win = fw(win, selector("initWithContentRect:styleMask:backing:defer:"),
             NSMakeRect(0, 0, 380, 110), xx NSWindowStyleMaskTitled, xx NSBackingStoreBuffered, 0);
    send_p(win, selector("setTitle:"), nss("Set Shortcut"));

    rv := objc_alloc_id(g_recorder_class);
    frv : (*void, Selector, NSRect) -> *void #c_call = xx objc_msgSend;
    rv = frv(rv, selector("initWithFrame:"), NSMakeRect(0, 0, 380, 110));
    send_p(win, selector("setContentView:"), rv);

    label := make_label("Press the shortcut you want…\n(Esc to cancel)", NSMakeRect(20, 30, 340, 50));
    send_p(rv, selector("addSubview:"), label);

    NSApplication.activateIgnoringOtherApps(NSApp, YES);
    send(win, selector("center"));
    send_p(win, selector("makeKeyAndOrderFront:"), null);
    send_p(win, selector("makeFirstResponder:"), rv);
    g_recorder_window = win;
}

close_recorder :: () {
    if g_recorder_window {
        send(g_recorder_window, selector("close"));
        g_recorder_window = null;
    }
}

// Returns true if the event was consumed (valid combo or Esc cancel).
recorder_capture :: (event: id) -> bool {
    temp_scope();
    kc   := event_keycode(event);
    nsfl := event_modflags(event);

    if kc == 53 {  // Esc → cancel
        close_recorder();
        return true;
    }

    mods := ns_mods_to_carbon(nsfl);
    if !valid_combo(kc, mods)  return false;  // need a real modifier (or F-key); keep waiting

    g_hotkey_keycode = kc;
    g_hotkey_mods    = mods;
    set_persistent_string(*g_hotkey_label, format_shortcut(kc, mods, event_chars(event)));
    apply_current_hotkey();
    save_hotkey();
    update_shortcut_menu_title();
    log_line(tprint("shortcut set: %", g_hotkey_label));
    close_recorder();
    return true;
}

valid_combo :: (keycode: u32, mods: u32) -> bool {
    if mods & (MOD_CMD | MOD_CONTROL | MOD_OPTION)  return true;
    return is_function_key(keycode);
}

ns_mods_to_carbon :: (f: u64) -> u32 {
    m: u32;
    if f & 0x100000  m |= MOD_CMD;      // Command (1<<20)
    if f & 0x040000  m |= MOD_CONTROL;  // Control (1<<18)
    if f & 0x080000  m |= MOD_OPTION;   // Option  (1<<19)
    if f & 0x020000  m |= MOD_SHIFT;    // Shift   (1<<17)
    return m;
}

format_shortcut :: (keycode: u32, mods: u32, chars: string) -> string {
    sb: String_Builder;
    if mods & MOD_CONTROL  append(*sb, "⌃");
    if mods & MOD_OPTION   append(*sb, "⌥");
    if mods & MOD_SHIFT    append(*sb, "⇧");
    if mods & MOD_CMD      append(*sb, "⌘");
    append(*sb, key_name(keycode, chars));
    return builder_to_string(*sb);
}

key_name :: (keycode: u32, chars: string) -> string {
    if keycode == {
        case 49;  return "Space";
        case 36;  return "Return";
        case 48;  return "Tab";
        case 51;  return "Delete";
        case 123; return "Left";
        case 124; return "Right";
        case 125; return "Down";
        case 126; return "Up";
    }
    fn := function_key_name(keycode);
    if fn  return fn;
    if chars.count > 0 {
        u := copy_string(chars);
        if u[0] >= #char "a" && u[0] <= #char "z"  u[0] -= 32;  // uppercase first
        return u;
    }
    return tprint("key%", keycode);
}

FKEYS :: u32.[122,120,99,118,96,97,98,100,101,109,103,111];  // F1..F12

is_function_key :: (keycode: u32) -> bool {
    for FKEYS  if it == keycode  return true;
    return false;
}

function_key_name :: (keycode: u32) -> string {
    for FKEYS  if it == keycode  return tprint("F%", it_index + 1);
    return "";
}

// --- API key dialog --------------------------------------------------------

prompt_set_api_key :: () {
    temp_scope();
    NSApplication.activateIgnoringOtherApps(NSApp, YES);

    alert := send(objc_alloc(objc_getClass("NSAlert")), selector("init"));
    send_p(alert, selector("setMessageText:"),     nss("Groq API Key"));
    send_p(alert, selector("setInformativeText:"), nss("Paste your Groq API key (starts with gsk_)."));
    send_p(alert, selector("addButtonWithTitle:"), nss("Save"));
    send_p(alert, selector("addButtonWithTitle:"), nss("Cancel"));

    field := make_text_field(g_api_key);
    send_p(alert, selector("setAccessoryView:"), field);
    win := send(alert, selector("window"));
    send_p(win, selector("setInitialFirstResponder:"), field);

    if run_modal(alert) == 1000 {  // NSAlertFirstButtonReturn = Save
        key := trim(nsstring_to_string(send(field, selector("stringValue"))));
        save_api_key(key);
        set_persistent_string(*g_api_key, key);
        g_have_key = key.count > 0;
        log_line("API key updated");
    }
}

// --- permissions helpers ---------------------------------------------------

BUNDLE_ID :: "com.arnaud.squirrelwhisperer";

build_permissions_submenu :: (target: *void) -> *void {
    menu := send(objc_alloc(objc_getClass("NSMenu")), selector("init"));
    add_menu_item(menu, "Open Microphone Settings…",    "openMicSettings:", target);
    add_menu_item(menu, "Open Accessibility Settings…", "openAxSettings:",  target);
    add_menu_item(menu, "Reset Permissions",            "resetPermissions:", target);
    return menu;
}

app_open_mic_settings :: () {
    temp_scope();
    run_command("open", "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone");
}

app_open_ax_settings :: () {
    temp_scope();
    run_command("open", "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility");
}

// Clears this app's grants so they can be re-requested (macOS has no API to grant).
app_reset_permissions :: () {
    temp_scope();
    run_command("tccutil", "reset", "Microphone",    BUNDLE_ID);
    run_command("tccutil", "reset", "Accessibility", BUNDLE_ID);
    log_line("permissions reset; Microphone re-prompts on next recording, re-add in Accessibility settings");
}

// --- persistence -----------------------------------------------------------

save_api_key :: (key: string) {
    dir := tprint("%/.config/whisper", home_dir());
    make_directory_if_it_does_not_exist(dir, recursive=true);
    write_entire_file(tprint("%/config", dir), tprint("export GROQ_API_KEY=\"%\"\n", key));
}

hotkey_file :: () -> string {
    return tprint("%/.cache/voice_input_hotkey", home_dir());
}

// Stored as "<keycode> <mods> <label>" (label has no spaces).
load_hotkey :: () {
    set_persistent_string(*g_hotkey_label, DEFAULT_LABEL);  // default until overridden below

    contents, ok := read_entire_file(hotkey_file());
    if !ok return;
    defer free(contents);
    parts := split(trim(contents), " ");
    defer array_free(parts);
    if parts.count < 3 return;
    g_hotkey_keycode = xx string_to_int(parts[0]);
    g_hotkey_mods    = xx string_to_int(parts[1]);
    set_persistent_string(*g_hotkey_label, parts[2]);
}

save_hotkey :: () {
    make_directory_if_it_does_not_exist(tprint("%/.cache", home_dir()), recursive=true);
    write_entire_file(hotkey_file(), tprint("% % %", g_hotkey_keycode, g_hotkey_mods, g_hotkey_label));
}

// --- small objc helpers ----------------------------------------------------

event_keycode :: (event: id) -> u32 {
    f : (*void, Selector) -> u16 #c_call = xx objc_msgSend;
    return f(event, selector("keyCode"));
}

event_modflags :: (event: id) -> u64 {
    f : (*void, Selector) -> u64 #c_call = xx objc_msgSend;
    return f(event, selector("modifierFlags"));
}

event_chars :: (event: id) -> string {
    return nsstring_to_string(send(event, selector("charactersIgnoringModifiers")));
}

make_text_field :: (initial: string) -> *void {
    tf := objc_alloc(objc_getClass("NSTextField"));
    f : (*void, Selector, NSRect) -> *void #c_call = xx objc_msgSend;
    tf = f(tf, selector("initWithFrame:"), NSMakeRect(0, 0, 480, 24));  // wide enough for a gsk_ key
    send_p(tf, selector("setStringValue:"), nss(initial));
    return tf;
}

make_label :: (text: string, rect: NSRect) -> *void {
    tf := objc_alloc(objc_getClass("NSTextField"));
    f : (*void, Selector, NSRect) -> *void #c_call = xx objc_msgSend;
    tf = f(tf, selector("initWithFrame:"), rect);
    send_p(tf, selector("setStringValue:"), nss(text));
    set_bool(tf, "setBezeled:",        false);
    set_bool(tf, "setEditable:",       false);
    set_bool(tf, "setSelectable:",     false);
    set_bool(tf, "setDrawsBackground:", false);
    return tf;
}

nsstring_to_string :: (ns: *void) -> string {
    if !ns return "";
    f : (*void, Selector) -> *u8 #c_call = xx objc_msgSend;
    c := f(ns, selector("UTF8String"));
    if !c return "";
    return copy_string(to_string(c));
}

run_modal :: (alert: *void) -> s64 {
    f : (*void, Selector) -> s64 #c_call = xx objc_msgSend;
    return f(alert, selector("runModal"));
}

set_bool :: (obj: *void, sel: string, v: bool) {
    f : (*void, Selector, BOOL) -> *void #c_call = xx objc_msgSend;
    f(obj, selector(sel), ifx v then cast(BOOL) 1 else cast(BOOL) 0);
}

objc_alloc_id :: (cls: Class) -> *void {
    f : (Class, Selector) -> *void #c_call = xx objc_msgSend;
    return f(cls, selector("alloc"));
}
