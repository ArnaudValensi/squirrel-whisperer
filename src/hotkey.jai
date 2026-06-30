// Native global hotkey via the Carbon Event Manager (RegisterEventHotKey).
// Works system-wide regardless of focus, needs no Accessibility permission,
// and keeps the app fully self-contained. The binding is user-selectable
// (see settings.jai) and can be changed at runtime.

EventHotKeyRef      :: *void;
EventHandlerRef     :: *void;
EventHandlerCallRef :: *void;
EventRef            :: *void;
EventTargetRef      :: *void;

EventHotKeyID :: struct { signature: u32; id: u32; }
EventTypeSpec :: struct { eventClass: u32; eventKind: u32; }

Event_Handler_Proc :: #type (next: EventHandlerCallRef, event: EventRef, user_data: *void) -> OSStatus #c_call;

kEventClassKeyboard :: 0x6b65_7962;  // 'keyb'
kEventHotKeyPressed :: 6;
HOTKEY_SIGNATURE    :: 0x7663_6870;  // 'vchp'

// Carbon modifier masks.
MOD_CMD     :: 0x0100;
MOD_SHIFT   :: 0x0200;
MOD_OPTION  :: 0x0800;
MOD_CONTROL :: 0x1000;

g_hotkey_ref: EventHotKeyRef;

// Install the event handler once (the hotkey itself is set via set_hotkey).
install_hotkey_handler :: () {
    spec := EventTypeSpec.{ eventClass = kEventClassKeyboard, eventKind = kEventHotKeyPressed };
    InstallEventHandler(GetApplicationEventTarget(), hotkey_handler, 1, *spec, null, null);
}

// Register (or re-register) the active hotkey.
set_hotkey :: (keycode: u32, modifiers: u32) {
    if g_hotkey_ref != null {
        UnregisterEventHotKey(g_hotkey_ref);
        g_hotkey_ref = null;
    }
    hk_id := EventHotKeyID.{ signature = HOTKEY_SIGNATURE, id = 1 };
    status := RegisterEventHotKey(keycode, modifiers, hk_id, GetApplicationEventTarget(), 0, *g_hotkey_ref);
    if status != 0  log_line(tprint("RegisterEventHotKey failed: %", status));
}

hotkey_handler :: (next: EventHandlerCallRef, event: EventRef, user_data: *void) -> OSStatus #c_call {
    g_toggle_pending = true;
    return 0;
}

#scope_file
Carbon :: #system_library "Carbon";

GetApplicationEventTarget :: () -> EventTargetRef #foreign Carbon;
InstallEventHandler :: (target: EventTargetRef, handler: Event_Handler_Proc, num_types: u64, list: *EventTypeSpec, user_data: *void, out_ref: *EventHandlerRef) -> OSStatus #foreign Carbon;
RegisterEventHotKey :: (code: u32, modifiers: u32, id: EventHotKeyID, target: EventTargetRef, options: u32, out_ref: *EventHotKeyRef) -> OSStatus #foreign Carbon;
UnregisterEventHotKey :: (ref: EventHotKeyRef) -> OSStatus #foreign Carbon;
