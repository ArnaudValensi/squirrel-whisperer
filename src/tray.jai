// Menu-bar (tray) UI via AppKit, driven through the Objective-C runtime.
// NSStatusItem/NSMenu aren't pre-bound, so we message them directly with
// objc_msgSend + selector().

// --- small objc helpers ---------------------------------------------------

// Autoreleased NSString — reclaimed by the per-event autorelease pool (temp_scope).
nss :: (s: string) -> *NSString {
    f : (Class, Selector, *u8) -> *NSString #c_call = xx objc_msgSend;
    return f(objc_getClass("NSString"), selector("stringWithUTF8String:"), temp_c_string(s));
}

send :: (self: *void, sel: Selector) -> *void {
    return objc_msgSend_typed(self, sel);
}

send_p :: (self: *void, sel: Selector, a: *void) -> *void {
    f : (*void, Selector, *void) -> *void #c_call = xx objc_msgSend;
    return f(self, sel, a);
}

// --- status item + menu ----------------------------------------------------

create_status_item :: () -> *void {
    bar := send(objc_getClass("NSStatusBar"), selector("systemStatusBar"));
    f : (*void, Selector, float64) -> *void #c_call = xx objc_msgSend;
    return f(bar, selector("statusItemWithLength:"), -1.0);  // NSVariableStatusItemLength
}

set_status_title :: (item: *void, title: string) {
    btn := send(item, selector("button"));
    if !btn return;
    send_p(btn, selector("setTitle:"), nss(title));
}

build_menu :: (item: *void, target: *void) {
    menu := send(objc_alloc(objc_getClass("NSMenu")), selector("init"));

    g_lang_menu_item = add_menu_item(menu, lang_menu_title(), "toggleLang:", target);
    g_shortcut_parent_item = add_submenu_item(menu, shortcut_menu_title(), build_shortcut_submenu(target));
    add_menu_item(menu, "Set Groq API Key…", "setApiKey:", target);
    add_submenu_item(menu, "Permissions", build_permissions_submenu(target));
    add_separator(menu);
    add_menu_item(menu, "Open logs", "openLogs:", target);
    add_separator(menu);
    add_menu_item(menu, "Quit The Squirrel Whisperer", "quitApp:", target);

    send_p(item, selector("setMenu:"), menu);
}

// A parent item that opens a submenu (no action of its own).
add_submenu_item :: (menu: *void, title: string, submenu: *void) -> *void {
    mi := objc_alloc(objc_getClass("NSMenuItem"));
    f : (*void, Selector, *void, Selector, *void) -> *void #c_call = xx objc_msgSend;
    mi = f(mi, selector("initWithTitle:action:keyEquivalent:"), nss(title), null, nss(""));
    send_p(mi, selector("setSubmenu:"), submenu);
    send_p(menu, selector("addItem:"), mi);
    return mi;
}

add_menu_item :: (menu: *void, title: string, action: string, target: *void) -> *void {
    mi := objc_alloc(objc_getClass("NSMenuItem"));
    f : (*void, Selector, *void, Selector, *void) -> *void #c_call = xx objc_msgSend;
    mi = f(mi, selector("initWithTitle:action:keyEquivalent:"), nss(title), selector(action), nss(""));
    send_p(mi, selector("setTarget:"), target);
    send_p(menu, selector("addItem:"), mi);
    return mi;
}

add_separator :: (menu: *void) {
    sep := send(objc_getClass("NSMenuItem"), selector("separatorItem"));
    send_p(menu, selector("addItem:"), sep);
}

// Install a main menu with an Edit submenu so text fields (e.g. the API key
// dialog) get the standard Cmd+C/V/X/A. An LSUIElement app has no menu bar, but
// these key equivalents still work for the app's key window / modal dialogs.
install_edit_menu :: (app: *void) {
    main_menu := send(objc_alloc(objc_getClass("NSMenu")), selector("init"));

    // A leading (empty) app menu so Edit isn't the first item.
    add_submenu_item(main_menu, "", send(objc_alloc(objc_getClass("NSMenu")), selector("init")));

    edit_menu := send(objc_alloc(objc_getClass("NSMenu")), selector("init"));
    add_edit_item(edit_menu, "Cut",        "cut:",       "x");
    add_edit_item(edit_menu, "Copy",       "copy:",      "c");
    add_edit_item(edit_menu, "Paste",      "paste:",     "v");
    add_edit_item(edit_menu, "Select All", "selectAll:", "a");
    add_submenu_item(main_menu, "Edit", edit_menu);

    send_p(app, selector("setMainMenu:"), main_menu);
}

// Edit item with no target → the action routes to the first responder (the
// focused text field's field editor), which implements cut:/copy:/paste:/selectAll:.
add_edit_item :: (menu: *void, title: string, action: string, key: string) {
    mi := objc_alloc(objc_getClass("NSMenuItem"));
    f : (*void, Selector, *void, Selector, *void) -> *void #c_call = xx objc_msgSend;
    mi = f(mi, selector("initWithTitle:action:keyEquivalent:"), nss(title), selector(action), nss(key));
    send_p(menu, selector("addItem:"), mi);
}

// --- app delegate (menu/timer callbacks) -----------------------------------

AppDelegate :: struct {
    using #as super: NSObject;

    onTimer :: (self: *AppDelegate, _sel: Selector, timer: id) #c_call {
        push_context { app_on_timer(); }
    } @selector(onTimer:)

    toggleLang :: (self: *AppDelegate, _sel: Selector, sender: id) #c_call {
        push_context { app_toggle_language(); }
    } @selector(toggleLang:)

    openLogs :: (self: *AppDelegate, _sel: Selector, sender: id) #c_call {
        push_context { app_open_logs(); }
    } @selector(openLogs:)

    quitApp :: (self: *AppDelegate, _sel: Selector, sender: id) #c_call {
        push_context { app_quit(); }
    } @selector(quitApp:)

    setApiKey :: (self: *AppDelegate, _sel: Selector, sender: id) #c_call {
        push_context { prompt_set_api_key(); }
    } @selector(setApiKey:)

    recordShortcut :: (self: *AppDelegate, _sel: Selector, sender: id) #c_call {
        push_context { app_record_shortcut(); }
    } @selector(recordShortcut:)

    resetShortcut :: (self: *AppDelegate, _sel: Selector, sender: id) #c_call {
        push_context { app_reset_shortcut(); }
    } @selector(resetShortcut:)

    openMicSettings :: (self: *AppDelegate, _sel: Selector, sender: id) #c_call {
        push_context { app_open_mic_settings(); }
    } @selector(openMicSettings:)

    openAxSettings :: (self: *AppDelegate, _sel: Selector, sender: id) #c_call {
        push_context { app_open_ax_settings(); }
    } @selector(openAxSettings:)

    resetPermissions :: (self: *AppDelegate, _sel: Selector, sender: id) #c_call {
        push_context { app_reset_permissions(); }
    } @selector(resetPermissions:)
}

register_delegate :: () -> *void {
    c := objc_create_class(AppDelegate, NSObject);
    objc_add_instance_method(c, AppDelegate.onTimer,        "onTimer:");
    objc_add_instance_method(c, AppDelegate.toggleLang,     "toggleLang:");
    objc_add_instance_method(c, AppDelegate.openLogs,       "openLogs:");
    objc_add_instance_method(c, AppDelegate.quitApp,        "quitApp:");
    objc_add_instance_method(c, AppDelegate.setApiKey,       "setApiKey:");
    objc_add_instance_method(c, AppDelegate.recordShortcut,   "recordShortcut:");
    objc_add_instance_method(c, AppDelegate.resetShortcut,    "resetShortcut:");
    objc_add_instance_method(c, AppDelegate.openMicSettings,  "openMicSettings:");
    objc_add_instance_method(c, AppDelegate.openAxSettings,   "openAxSettings:");
    objc_add_instance_method(c, AppDelegate.resetPermissions, "resetPermissions:");
    objc_finalize_class(c);

    inst := objc_alloc(c);
    return send(inst, selector("init"));
}
