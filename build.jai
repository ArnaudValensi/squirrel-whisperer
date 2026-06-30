#run build();

// Build metaprogram for The Squirrel Whisperer.
//
//   jai build.jai - build         dev build (IS_DEV: memory debugger + leak report on)
//   jai build.jai - build-prod    release build (IS_DEV off)
//   jai build.jai - build-tests   build the unit-test executable into ./build
//   jai build.jai - install       dev build + install into ~/Applications
//   jai build.jai - install-prod  release build + install (use this for daily use)
//   jai build.jai - release        prod build, signed + hardened + notarized DMG
//
// Modeled on the oob-jai build conventions.

build :: () {
    set_working_directory(#filepath);

    options := get_build_options();
    args := options.compile_time_command_line;

    if array_find(args, "release") {
        release();
    } else if array_find(args, "build-tests") {
        build_target("./src/tests.jai", "tests", is_dev=true, bundle=false);
    } else if array_find(args, "build-prod") {
        build_target("./src/main.jai", "SquirrelWhisperer", is_dev=false, bundle=true);
    } else if array_find(args, "install-prod") {
        build_target("./src/main.jai", "SquirrelWhisperer", is_dev=false, bundle=true);
        install_app();
    } else if array_find(args, "install") {
        build_target("./src/main.jai", "SquirrelWhisperer", is_dev=true, bundle=true);
        install_app();
    } else {
        build_target("./src/main.jai", "SquirrelWhisperer", is_dev=true, bundle=true);
    }

    set_build_options_dc(.{do_output=false});  // no executable for this build workspace
}

// is_dev injects IS_DEV (toggles MEMORY_DEBUGGER + leak diagnostics in the app).
build_target :: (entry: string, exe_name: string, is_dev: bool, bundle: bool) {
    make_directory_if_it_does_not_exist("./build");

    w := compiler_create_workspace();
    options := get_build_options(w);
    options.output_path = "./build";
    options.output_executable_name = exe_name;
    options.backend = .LLVM;
    set_build_options(options, w);

    compiler_begin_intercept(w);
    add_build_string(tprint("IS_DEV :: %;", is_dev), w);
    add_build_file(entry, w);

    while true {
        message := compiler_wait_for_message();
        if message.workspace != w continue;
        if message.kind == {
            case .ERROR; exit(1);
            case .COMPLETE; break;
        }
    }
    compiler_end_intercept(w);

    if bundle {
        exe_path := tprint("%/%", options.output_path, exe_name);
        // Bundled dylibs the exe loads via @loader_path rpath.
        copy_dep_dylib(options.output_path, options.import_path, "SDL/macos/libSDL2.dylib", "libSDL2.dylib");
        copy_dep_dylib(options.output_path, options.import_path, "Curl/macos/lib/libcurl.dylib", "libcurl.dylib");
        make_app_bundle(exe_name, exe_path, options.output_path);
        print("\n✅ Build complete: ./build/%.app\n", exe_name);
    } else {
        print("\n✅ Tests built: ./build/%\n", exe_name);
    }
}

// Install into ~/Applications. On update we overwrite the bundle's payload
// IN PLACE (never `rm -rf` the bundle) and re-sign there, so the app keeps the
// same on-disk identity and macOS keeps the Microphone/Accessibility grants.
install_app :: () {
    home := to_string(getenv(temp_c_string("HOME")));
    dest := tprint("%/Applications/SquirrelWhisperer.app", home);
    src  := "./build/SquirrelWhisperer.app";

    if !file_exists(tprint("%/Contents/Info.plist", dest)) {
        run_command("cp", "-R", src, dest);   // first install: full copy
        print("\n✅ Installed: %\n", dest);
        print("   Launch it, grant Microphone (first recording) and Accessibility\n");
        print("   (System Settings > Privacy > Accessibility > +).\n");
        return;
    }

    // Update in place: replace each payload file (rm+cp is safe for a running
    // binary — unlink keeps the live inode), then re-sign the existing bundle.
    replace_in_bundle(src, dest, "Contents/MacOS/SquirrelWhisperer");
    replace_in_bundle(src, dest, "Contents/MacOS/libSDL2.dylib");
    replace_in_bundle(src, dest, "Contents/MacOS/libcurl.dylib");
    replace_in_bundle(src, dest, "Contents/Info.plist");
    codesign_app(dest);

    print("\n✅ Updated in place: %\n", dest);
    print("   (permissions preserved — quit & relaunch the app to pick up changes)\n");
}

replace_in_bundle :: (src: string, dest: string, rel: string) {
    run_command("rm", "-f", tprint("%/%", dest, rel));
    run_command("cp", tprint("%/%", src, rel), tprint("%/%", dest, rel));
}

// Produce a notarized, stapled DMG for distribution to other Macs. Without
// notarization a downloaded (quarantined) build trips Gatekeeper's "Apple cannot
// check it for malicious software". We notarize BOTH the .app and the DMG and
// staple each, so the app launches cleanly even on a Mac that is offline at first
// launch. Requires a Developer ID (notarization rejects ad-hoc / self-signed) and
// a one-time `xcrun notarytool store-credentials <profile>` set up by the user.
release :: () {
    id_c := getenv(temp_c_string("SQUIRREL_SIGN_IDENTITY"));
    if !id_c {
        print("\n⚠️  release needs a Developer ID. Set SQUIRREL_SIGN_IDENTITY, e.g.\n");
        print("    export SQUIRREL_SIGN_IDENTITY=\"Developer ID Application: Your Name (TEAMID)\"\n");
        exit(1);
    }
    id := to_string(id_c);
    if !begins_with(id, "Developer ID") {
        print("\n⚠️  notarization requires a 'Developer ID Application' identity; got '%'.\n", id);
        exit(1);
    }

    prof_c := getenv(temp_c_string("SQUIRREL_NOTARY_PROFILE"));
    profile := ifx prof_c then to_string(prof_c) else "squirrel-notary";

    // 1. Prod build + bundle (IS_DEV off). This also signs the bundle once; we
    //    re-sign below with the hardened runtime + entitlements that notarization needs.
    build_target("./src/main.jai", "SquirrelWhisperer", is_dev=false, bundle=true);

    app := "./build/SquirrelWhisperer.app";

    // 2. Re-sign for release: hardened runtime + secure timestamp, signed inside-out
    //    (nested dylibs first, then the bundle with the mic entitlement on the exe).
    //    Same Developer ID team on every Mach-O => library validation passes; no
    //    --deep (Apple-deprecated) and no disable-library-validation needed.
    ent := "./build/entitlements.plist";
    write_entire_file(ent, ENTITLEMENTS);
    sign_runtime(tprint("%/Contents/MacOS/libSDL2.dylib", app), id, "");
    sign_runtime(tprint("%/Contents/MacOS/libcurl.dylib", app), id, "");
    sign_runtime(app, id, ent);

    vr := run_command("codesign", "--verify", "--strict", "--verbose=2", app);
    if vr.exit_code != 0 { print("\n⚠️  codesign verification failed.\n"); exit(1); }

    // 3. Notarize + staple the .app (zip via ditto, which preserves the bundle).
    zip := "./build/SquirrelWhisperer.zip";
    run_command("rm", "-f", zip);
    dr := run_command("ditto", "-c", "-k", "--keepParent", app, zip);
    if dr.exit_code != 0 { print("\n⚠️  ditto zip of the app failed.\n"); exit(1); }
    notarize(zip, profile);
    staple(app);

    // 4. Build the DMG from the now-stapled app (+ /Applications drag target).
    dmg := build_dmg(app);

    // 5. Notarize + staple the DMG itself, then validate the staple.
    notarize(dmg, profile);
    staple(dmg);
    vd := run_command("xcrun", "stapler", "validate", dmg);
    if vd.exit_code != 0 { print("\n⚠️  stapler validate failed for %.\n", dmg); exit(1); }

    print("\n✅ Release ready: %\n", dmg);
    print("   Notarized + stapled (app and DMG). Distribute this DMG.\n");
}

// codesign with the hardened runtime and a secure timestamp (both required for
// notarization). Pass an entitlements plist for the main executable; "" for dylibs.
sign_runtime :: (path: string, id: string, entitlements: string) {
    res: Process_Result;
    if entitlements {
        res = run_command("codesign", "--force", "--options", "runtime", "--timestamp",
                          "--entitlements", entitlements, "--sign", id, path);
    } else {
        res = run_command("codesign", "--force", "--options", "runtime", "--timestamp",
                          "--sign", id, path);
    }
    if res.exit_code != 0 { print("\n⚠️  codesign --options runtime failed for %.\n", path); exit(1); }
    print("   hardened-signed %\n", path);
}

// Upload to Apple's automated notary service and block until it finishes (minutes).
notarize :: (path: string, profile: string) {
    print("\n📤 Notarizing % via Apple (keychain-profile '%')...\n", path, profile);
    res := run_command("xcrun", "notarytool", "submit", path, "--keychain-profile", profile, "--wait");
    if res.exit_code != 0 {
        print("\n⚠️  notarization failed for %.\n", path);
        print("    If credentials are missing, run once:\n");
        print("      xcrun notarytool store-credentials \"%\" --apple-id <id> --team-id 62HEYVWMQD --password <app-specific-pw>\n", profile);
        print("    For rejection details: xcrun notarytool log <submission-id> --keychain-profile \"%\"\n", profile);
        exit(1);
    }
}

staple :: (path: string) {
    res := run_command("xcrun", "stapler", "staple", path);
    if res.exit_code != 0 { print("\n⚠️  stapler staple failed for %.\n", path); exit(1); }
    print("   stapled %\n", path);
}

// hdiutil-built UDZO DMG with the app + an /Applications symlink (drag to install).
build_dmg :: (app: string) -> string {
    staging := "./build/dmg-staging";
    run_command("rm", "-rf", staging);
    make_directory_if_it_does_not_exist(staging, recursive=true);
    run_command("cp", "-R", app, tprint("%/SquirrelWhisperer.app", staging));
    run_command("ln", "-s", "/Applications", tprint("%/Applications", staging));

    dmg := "./build/SquirrelWhisperer.dmg";
    run_command("rm", "-f", dmg);
    res := run_command("hdiutil", "create", "-volname", "The Squirrel Whisperer",
                       "-srcfolder", staging, "-ov", "-format", "UDZO", dmg);
    if res.exit_code != 0 { print("\n⚠️  hdiutil create failed.\n"); exit(1); }
    return dmg;
}

getenv :: (name: *u8) -> *u8 #foreign LibC "getenv";
LibC :: #system_library "libc";

copy_dep_dylib :: (out_dir: string, import_path: [] string, rel: string, dest_name: string) {
    for import_path {
        src := tprint("%/%", it, rel);
        if file_exists(src) {
            ok := copy_file(src, tprint("%/%", out_dir, dest_name));
            if !ok { print("⚠️  failed to copy %\n", src); exit(1); }
            return;
        }
    }
    print("⚠️  % not found in import paths: %\n", rel, import_path);
    exit(1);
}

// Build a minimal .app bundle and ad-hoc sign it. The bundle is what holds the
// Microphone + Accessibility TCC permissions; LSUIElement keeps it off the Dock;
// NSMicrophoneUsageDescription is mandatory for the mic prompt to appear.
make_app_bundle :: (app_name: string, exe_path: string, out_dir: string) {
    app := tprint("%/%.app", out_dir, app_name);
    macos := tprint("%/Contents/MacOS", app);
    make_directory_if_it_does_not_exist(macos, recursive=true);

    ok1 := copy_file(exe_path, tprint("%/%", macos, app_name));
    ok2 := copy_file(tprint("%/libSDL2.dylib",  out_dir), tprint("%/libSDL2.dylib",  macos));
    ok3 := copy_file(tprint("%/libcurl.dylib", out_dir), tprint("%/libcurl.dylib", macos));
    if !ok1 || !ok2 || !ok3 {
        print("⚠️  bundle copy failed (exe=% sdl=% curl=%)\n", ok1, ok2, ok3);
        exit(1);
    }

    plist := tprint(PLIST_FMT, app_name);
    write_entire_file(tprint("%/Contents/Info.plist", app), plist);

    run_command("chmod", "+x", tprint("%/%", macos, app_name));
    codesign_app(app);
}

// Code-sign the bundle. By default this is ad-hoc, which works on any machine
// with no certificate or keychain access — the right behavior for contributors.
// Set SQUIRREL_SIGN_IDENTITY (e.g. in your shell profile) to a Developer ID and
// the build signs with it instead; only then do the Microphone/Accessibility
// grants persist across rebuilds. (Notarization is a separate `release` step.)
codesign_app :: (path: string) {
    id := getenv(temp_c_string("SQUIRREL_SIGN_IDENTITY"));
    if !id {
        run_command("codesign", "--force", "--deep", "--sign", "-", path);
        print("   ad-hoc signed (set SQUIRREL_SIGN_IDENTITY to a Developer ID for persistent permissions)\n");
        return;
    }

    name := to_string(id);
    res := run_command("codesign", "--force", "--deep", "--sign", name, path);
    if res.exit_code != 0 {
        print("   ⚠️  signing with '%' failed — using ad-hoc\n", name);
        run_command("codesign", "--force", "--deep", "--sign", "-", path);
    } else {
        print("   signed with '%'\n", name);
    }
}

PLIST_FMT :: #string PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>The Squirrel Whisperer</string>
    <key>CFBundleDisplayName</key>     <string>The Squirrel Whisperer</string>
    <key>CFBundleExecutable</key>      <string>%</string>
    <key>CFBundleIdentifier</key>      <string>com.arnaud.squirrelwhisperer</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>The Squirrel Whisperer records your microphone to transcribe speech.</string>
</dict>
</plist>
PLIST

// Entitlements for the hardened-runtime release build. The mic entitlement is
// mandatory under the hardened runtime; without it CoreAudio capture is denied.
ENTITLEMENTS :: #string ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
ENT

#import "Basic";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "String";
#import "Process";
