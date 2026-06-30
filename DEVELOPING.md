# Developing The Squirrel Whisperer

The app is a single Jai program that builds a self contained macOS `.app` bundle. All tooling
is in the `build.jai` metaprogram, there are no shell scripts.

## Prerequisites

- macOS
- The Jai compiler (built here with `jai-macos`)
- A Groq API key for runtime, from [console.groq.com](https://console.groq.com)

## Build, test, install

```bash
jai build.jai - build          # build ./build/SquirrelWhisperer.app
jai build.jai - build-tests    # build ./build/tests
./build/tests                  # run unit tests (config / wav / state) + leak report
jai build.jai - install        # build and install to ~/Applications/SquirrelWhisperer.app
```

(`jai` is the compiler, for example `~/dev/jai/bin/jai-macos`.)

## Signing and permissions

macOS keeps the Microphone and Accessibility grants only when the app keeps a stable code
signature. By default the build is **ad-hoc signed** (no certificate, no keychain access), so
it builds anywhere with zero setup but the grants reset on each rebuild during development. For
grants that persist across rebuilds, build with a real Developer ID by setting
`SQUIRREL_SIGN_IDENTITY` (put it in your shell profile so every build uses it):

```bash
SQUIRREL_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" jai build.jai - install
```

`install` updates the bundle in place and re-signs it, so a finished build keeps its grants.

## Release (notarized DMG for distribution)

To hand the app to other people, a downloaded build must be notarized or macOS blocks it
("Apple cannot check it for malicious software"). The `release` command does the whole flow:

```bash
jai build.jai - release   # -> ./build/SquirrelWhisperer.dmg (signed, hardened, notarized, stapled)
```

It builds prod, re-signs the app and bundled dylibs with the hardened runtime and a mic
entitlement, notarizes and staples the `.app`, packages a DMG, then notarizes and staples the
DMG. Both the app and the DMG are stapled, so the app launches cleanly even offline.

Prerequisites:

- `SQUIRREL_SIGN_IDENTITY` must be a `Developer ID Application:` identity (ad-hoc and self
  signed certs are rejected by notarization).
- A notarytool keychain profile, created once with your Apple ID and an app specific password:

  ```bash
  xcrun notarytool store-credentials "squirrel-notary" \
      --apple-id you@example.com --team-id 62HEYVWMQD --password <app-specific-password>
  ```

  Override the profile name with `SQUIRREL_NOTARY_PROFILE` (default `squirrel-notary`).

Notarization is automated (no human review) and usually takes a couple of minutes;
`notarytool submit --wait` blocks until Apple responds. On rejection, inspect the log with
`xcrun notarytool log <submission-id> --keychain-profile "squirrel-notary"`.

## Architecture

See [REQUIREMENTS.md](REQUIREMENTS.md) for the design, the source layout, and the component map.
