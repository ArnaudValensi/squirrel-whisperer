// Clipboard + paste. The clipboard is set natively via NSPasteboard; the ⌘V
// keystroke is synthesized directly with CGEvent (CoreGraphics) — no osascript /
// System Events, so the only permission involved is Accessibility (no Automation).

set_clipboard :: (text: string) {
    pb := NSPasteboard.generalPasteboard();
    NSPasteboard.clearContents(pb);
    NSPasteboard.setString(pb, nss(text), NSPasteboardTypeString);
}

paste_to_focused_app :: (text: string) {
    if text.count == 0 return;
    set_clipboard(text);
    SDL.SDL_Delay(20);   // let the focused app see the new clipboard
    press_cmd_v();
}

press_cmd_v :: () {
    KEY_V        : u16 : 9;          // ANSI 'v'
    FLAG_COMMAND : u64 : 0x100000;   // kCGEventFlagMaskCommand
    HID_TAP      : u32 : 0;          // kCGHIDEventTap

    down := CGEventCreateKeyboardEvent(null, KEY_V, true);
    CGEventSetFlags(down, FLAG_COMMAND);
    CGEventPost(HID_TAP, down);

    up := CGEventCreateKeyboardEvent(null, KEY_V, false);
    CGEventSetFlags(up, FLAG_COMMAND);
    CGEventPost(HID_TAP, up);

    CFRelease(down);
    CFRelease(up);
}

#scope_file
CoreGraphics   :: #system_library "CoreGraphics";
CoreFoundation :: #system_library "CoreFoundation";

CGEventCreateKeyboardEvent :: (source: *void, keycode: u16, keydown: bool) -> *void #foreign CoreGraphics;
CGEventSetFlags :: (event: *void, flags: u64) #foreign CoreGraphics;
CGEventPost :: (tap: u32, event: *void) #foreign CoreGraphics;
CFRelease :: (cf: *void) #foreign CoreFoundation;
