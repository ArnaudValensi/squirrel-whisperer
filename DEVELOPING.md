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

## Continuous integration (universal build on GitHub)

`.github/workflows/build.yml` builds a **universal** (Intel + Apple Silicon), signed and
notarized DMG and attaches it to the GitHub Release whenever a `v*` tag is pushed:

```bash
git tag v1.1 && git push origin v1.1
```

How it works: a matrix builds the thin executable on `macos-15-intel` and `macos-15` (Jai
targets the host CPU, so each arch needs its own runner) and uploads them as artifacts; a
fan-in `package` job runs `jai build.jai - package-universal`, which `lipo`-merges the two
executables (the SDL/Curl dylibs already ship universal, so they are copied as-is), then
hardened-signs, notarizes, and staples the app and the DMG exactly like the local `release`.

The Jai compiler is proprietary, so it must never be committed here or uploaded to this repo
(which is public). CI fetches it at build time from the **private** `jai-dist` release of
`ArnaudValensi/oob-jai`, authenticated with a fine-grained personal access token. This is safe
on a public repo because GitHub never exposes secrets to pull requests from forks, and this
workflow only runs on `v*` tag pushes (which require push access).

Create the token once at <https://github.com/settings/personal-access-tokens>: fine-grained,
**Resource owner** your account, **Only select repositories** > `oob-jai`, **Repository
permissions** > **Contents: Read-only**. Store it as the `JAI_DIST_PAT` secret. The zip there
must extract to a `jai/` folder containing `bin/jai-macos` and `modules/`.

Signing and notarization in CI need these **repository secrets**
(Settings > Secrets and variables > Actions):

| Secret | Value |
| --- | --- |
| `JAI_DIST_PAT` | fine-grained PAT, `oob-jai` only, Contents: Read-only |
| `MACOS_SIGN_IDENTITY` | `Developer ID Application: Arnaud Valensi (62HEYVWMQD)` |
| `MACOS_CERT_P12_BASE64` | base64 of the Developer ID cert **and** private key exported as `.p12` |
| `MACOS_CERT_PASSWORD` | the password chosen when exporting that `.p12` |
| `MACOS_NOTARY_APPLE_ID` | the Apple ID email used for notarization |
| `MACOS_NOTARY_TEAM_ID` | `62HEYVWMQD` |
| `MACOS_NOTARY_PASSWORD` | an app-specific password for that Apple ID |

Export the `.p12` from Keychain Access (select the `Developer ID Application` cert *and* its
private key > Export), then base64 it for the secret:

```bash
base64 -i DeveloperID.p12 | pbcopy   # paste into MACOS_CERT_P12_BASE64
```

`build.jai` reads the notary credentials from `SQUIRREL_NOTARY_APPLE_ID` / `_TEAM_ID` /
`_PASSWORD` when set (CI), and falls back to the local `notarytool` keychain profile otherwise,
so `jai build.jai - release` keeps working unchanged on your machine.

## Architecture

See [REQUIREMENTS.md](REQUIREMENTS.md) for the design, the source layout, and the component map.
