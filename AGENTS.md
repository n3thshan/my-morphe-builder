# AGENTS.md

Guidance for AI agents working in this repository. Read this before making any changes.

## What this is

**my-morphe-builder** — a personal project by [n3thshan](https://github.com/n3thshan), based on [j-hc/revanced-magisk-module](https://github.com/j-hc/revanced-magisk-module). It builds patched APKs in the cloud with GitHub Actions, using community Morphe patches.

The user is not a developer. **Write and talk in plain, simple English.** Ask questions instead of guessing. Do only what the user asks. Keep answers short.

The user uses **Notesnook**. The user's mom uses **Truecaller** and **Pinterest**. The user's uncle uses **Facebook**. Everything works today — keep it working.

**Google Photos** was removed from the project on 2026-11-07 at the user's confirmation. Do not re-add it without asking.

## The flow

`ci.yml` wakes every day (cron, 16:00 UTC — GitHub may delay it) or by hand → it checks whether anything a patch source ships changed → if so, `build.yml` downloads the stock APKs, patches them, signs them and publishes a new GitHub Release. Only the apps that changed are rebuilt and published; the others are skipped.

Releases contain only the changed apps, and release notes are the changelog. [Obtainium](https://obtainium.imranr.dev/) installs and updates the apps from this repo; the import file is [`obtainium-import.json`](./obtainium-import.json), and every app there has `fallbackToOlderReleases: true` (needed because a release does not always contain all apps).

## Audience and repo status

- The repo is **public** (GPL-3.0 license).
- The user builds apps mainly for personal use ("my personal set of APKs"), published publicly so others may use them too.
- Keep upstream attribution where it already exists; keep the `LICENSE`.
- Don't add template scaffolding, popularity polish, or public-facing docs unless the user asks.

## Hard constraints (do not violate)

1. **arm64-v8a only.** Never introduce other ABIs (no armeabi-v7a, x86, x86_64, multi-AB builds) without explicit approval from the user.
2. **Bundled keystores sign everything.** `ks.keystore` signs the final patched APKs; `ks-p12.keystore` signs the stock merge step. Do not add per-app key management. See "Signing keys" below before touching either file.
3. **APKPure stays the Truecaller, Pinterest and Facebook source.** Do not remove the `apkpure` download source, the apkeep workflow step, or the `arm64_ok` guard. Keep `apkeep -d apk-pure` as apkeep's only download source. Notesnook keeps the official Notesnook endpoint.
4. **`patches-version = "latest"`** is intentional, except **Pinterest**, deliberately pinned to `v0.0.5` (and `version = "14.25.0"`) by the user (2026-11-05): newer releases target Pinterest builds APKPure does not carry, and v0.0.6+ dropped `14.25.0` support. Don't unpin it until APKPure carries a build a newer patch release supports. The user wants all apps up to date — if a pin or source lag is blocking that, **tell the user and let them decide**. Never change a pin or source on your own.
5. **Don't bump app `version`s without checking patch support first.** Verify against the bundle's `patches-list.json` (hxreborn's for Notesnook; heval99/Heval-Morphe-Patches' for Truecaller; HushPinterest's for Pinterest; HushFacebook's for Facebook) and check the source serves that version.
6. **Agent edits files; the user pushes.** No commits or pushes unless the user explicitly asks. No `git remote` operations. No `gh` calls (there is no `gh` here).
7. **Don't add apps without asking.** The user has not decided on more apps yet. See "Adding an app" for the procedure if the user says yes.
8. **Download sources** are only the ones already in `config.toml`/`utils.sh` (`official-dlurl`, `apkpure-dlurl`, `direct-dlurl`, `archive-dlurl`, `apkmirror-dlurl`). No scraped or unofficial sources without the user's say-so.
9. **No Google Photos.** It was dropped 2026-11-07. If the user wants it back, tell them it needs a decision again — including package rename `app.morphe.android.apps.photos` vs official package, and force-patching.
10. **Facebook must keep the APKPure source and the superpack unpack.** Added 2026-11-12 by user decision (it was dropped earlier for lack of a free source for the patchable build). APKPure only serves the Android 9+ build (`com.facebook.katana` 586.0.0.52.53, minSdk 28), whose DEX files sit in a Superpack store the patcher can't read — so CI unpacks it on a temporary x86_64 Android emulator before patching. Don't change the source, the emulator step, `superpack_unpack()`, or the `superpack-ref` pin without asking. The pin (a main commit) exists only until a HushFacebook release ships the unpacker; dropping it then is the planned step, but confirm with the user first. The Android 11+ build (APKMirror, the patches' official target) is behind a Cloudflare challenge and can't be scraped reliably; that stays a manual download the user hasn't wanted.

## Signing keys (public, on purpose)

The repo is public, so the signing keys are public too. This matches the upstream project and other forks ([VVispy/morphe-builder](https://github.com/VVispy/morphe-builder) keeps the identical files). The user was told and confirmed: keep this setup, don't change it.

What this means:

- Passwords are hardcoded in `utils.sh` (`123456789`) — that is upstream's design, not a private secret.
- Anyone can sign an APK with the public key. A user installing from this repo trusts the build the same way they trust every upstream j-hc fork: by source, not by signature.
- Patched APKs cannot update over official/Play installs; that's accepted.
- If the user ever wants a new key, users must uninstall and reinstall every built app once. **Ask before** changing anything about signing.
- Signature verification (`sig.txt`) checks **none** of the current apps — all configured apps skip the check (`check_sig` is a no-op for them). Don't assume it protects anything here.

## Repository layout

| Path | Purpose |
|---|---|
| `build.sh` | Entry point: parses config, fetches patch/CLI prebuilts, downloads stock APKs, patches, signs, outputs to `build/` |
| `utils.sh` | All logic: download sources, `get_prebuilts`, `get_patch_last_supported_ver`, APKEditor merge for split bundles, signing, release-changelog assembly |
| `config.toml` | App tables (`[Notesnook]`, `[Truecaller]`, `[Pinterest]`); see the app section |
| `sig.txt` | Allowlist of stock-APK signature certs; **none of the current apps are listed**, so the check is a no-op |
| `obtainium-import.json` | Obtainium import file for the public builds — update it when apps/packages/filters change |
| `.github/workflows/ci.yml` | Daily cron 16:00 UTC + manual dispatch; decides whether to build; calls `build.yml` |
| `.github/workflows/build.yml` | Build + release flow — **still named "Build Modules"** (a leftover name; see Known issues). Boots a temporary x86_64 Android emulator first when an app with `superpack-unpack = true` is being built |
| `.gitattributes` | LF enforced for text, binary marking — do not remove or relax |
| `module/` | Magisk module template — **unused** (all apps are `build-mode = "apk"`); leave alone |
| `build-termux.sh` | **Stale upstream script** — it clones upstream, not this repo; don't use (see Known issues) |
| `bin/` | Prebuilt helpers (`apksigner.jar`, `aapt2`, `htmlq`, `tq` TOML parser, `paccer.jar`, `dexlib2.jar`) |

User keeps **`README.md`** short on purpose (rewritten 2026-11-07): apps list with patch-source links + Obtainium instructions. Do not restore the old long upstream README section. Small edits are fine when the apps change; don't rewrite it without asking.

**`CONFIG.md`** is the upstream, generic option reference — it does not match this project anymore (invalid example pins, invites non-arm64 builds, wrong claims about `parallel-jobs`). Treat it as historical reference only. Supported behavior is in `config.toml` comments and this file. Proposing a rewrite or deletion needs the user's approval.

## Current apps

| App | Patch source | Version | Source of stock APK | Notes |
|---|---|---|---|---|
| **Notesnook** | `hxreborn/morphe-patches` (`latest`) | `auto` (highest supported, currently **3.4.15**) | Official endpoint (`official-dlurl`, 302 → official asset) | hxreborn v1.73.0: supports 3.4.12–3.4.15. If the endpoint serves something newer than patches support, the patch step fails loudly — expected; wait or pin. |
| **Truecaller** | `heval99/Heval-Morphe-Patches` (`latest`) | `auto` (currently **26.43.5**) | APKPure via apkeep | heval v2.2.0: 30 patches, **26.43.5 only**, includes GmsCore support; package stays `com.truecaller`; merged from XAPK. |
| **Pinterest** | `SysAdminDoc/HushPinterest` (**`v0.0.5` pinned**) | **`14.25.0` pinned** | APKPure via apkeep | v0.0.5 = 23 patches, **no** GmsCore / push-notification patches (email + password login). APKPure only offers up to 14.25.0. **Temporary pin** (2026-11-05, user decision): unpin once APKPure mirrors a build a newer HushPinterest release supports, then tell the user first. |
| **Facebook** | `SysAdminDoc/HushFacebook` (`latest`) | `auto` (currently **586.0.0.52.53**) | APKPure via apkeep (Android 9+ build) | The Android 9+ build stores its DEX files in a Superpack archive. CI decodes it on a temporary x86_64 emulator (`superpack_unpack()` in `utils.sh`) into the Android 11+ layout before patching. Maintainer confirmed a patched unpack runs (Home/Reels) on Android 16; untested on Android 9/10 phones. Not in `sig.txt` (signature check skipped). |

Status as of 2026-11-12 (Facebook added); check patches-list.json and the APKPure API when you change anything.

## Building blocks and the state system

- The build only happens when something changed, compared against the `update` branch. `build-state.txt` is the per-app memory (one line per app: source, patch asset, asset digest, configured version); `build.md` is only the migration fallback.
- A partial release is **normal**: it contains only the apps that changed. This is why Obtainium needs `fallbackToOlderReleases: true`.
- The daily CI: cron `0 16 * * *` UTC; GitHub delays scheduled runs (seen at ~21:00). Manual dispatch: **CI** workflow. Force a full rebuild: **Build Modules** workflow → run with `force_all = true` (the `CI` workflow has no `force_all` input).
- The `update` branch holds `build.md`, `build-state.txt` and a long-unused `dummy-update.json`. CI owns it; don't hand-edit `build-state.txt`. To force a rebuild deliberately, use `force_all`. To reset history deliberately, delete `build-state.txt` and then manually run the **Build Modules** workflow once (the cron alone will not re-seed it).
- Release notes are generated from the build log; they currently contain stale YouTube/MicroG lines and can show a wrong "Skipped" list (see Known issues).
- `--config-update` in `build.sh` decides what to build. `build.yml` builds and publishes a numbered release (title `Release`).

## Known issues and risks (observed 2026-11-07, not fixed — user decides)

1. **Pinterest can rebuild every day.** `build-state.txt` stores the fingerprint of the downloaded patch file *after* the builder modifies it, while the change check compares it against the original release asset's fingerprint. Bundles with `extensions/shared.*` (HushPinterest v0.0.5 has one) always mismatch. (Google Photos suffered the same until it was removed.)
2. **Silent failures.** If one app fails to build, the others still ship and CI stays green; the release body may still list the failed app. Check the release's assets and the CI log when something looks off, don't trust the release text alone.
3. **`build.yml` is named "Build Modules"** and still carries module logic; all apps are APK-only.
4. **The "Update config" step in `build.yml` has no `GITHUB_TOKEN`**, so patch-source checks use the 60/hour anonymous GitHub API limit; if everything rate-limits, the job fails.
5. **`parallel-jobs` is ignored** — the build always runs serially. `version = "beta"` is documented in CONFIG.md but not implemented.
6. **`config_update` ignores** CLI version changes, included/excluded patches, `patcher-args`, `apkpure-dlurl`, `app-name`, `arch`, `build-mode` — changing only those does not trigger rebuilds; use `force_all`.
7. **Release notes** always contain YouTube/MicroG lines and can contain wrong "Skipped" entries.
8. **`build.sh`** ignores a failing background app less strictly than it should, writes the app name to the release notes *before* patching finishes, and can abort the whole run if a background job errors early in `auto` mode.
9. **`CONFIG.md`** is stale and invites non-arm64 builds; don't point users at it.
10. **`wrapper` mismatch:** `utils.sh` first tries `list-patches --versions --packages -b` — those flags don't exist in Morphe CLI 2.x, so the fallback does the work (harmless, wasteful).
11. **`obtainium-import.json`** is hand-maintained (`exportedAt` is a placeholder, `appVersion` is `0.0.0`); it has no CI validation. Keep the filters in sync with `app-name` and the package IDs.
12. **`sig.txt`** matches nothing — signature checks are effectively disabled for all apps.
13. **Both workflows have `permissions: write-all`** — broader than needed.
14. **Stale leftovers:** `build-termux.sh` (clones upstream), the `module/` folder, the ReVanced-era bug report template, `dummy-update.json` on the `update` branch, `bin/htmlq` and `bin/aapt2` (only used on dead code paths).
15. **Facebook's CI unpack needs the emulator.** If the x86_64 emulator fails to boot (no KVM, sdkmanager trouble, image download flake), the `Boot Android emulator` step fails and — with default GitHub Actions behavior — the whole job stops before `build.sh` runs. The other apps are not rebuilt that day either. If you'd rather a Facebook failure not block the rest, that needs a decision (and probably `continue-on-error` on the emulator step).
16. **`config_update` ignores `superpack-unpack` and `superpack-ref`.** Changing only those keys (or the emulator setup) doesn't trigger a rebuild; use `force_all`. Also, the Android 9+ DEX compatibility with HushFacebook's patches is maintainer-confirmed only for Home/Reels — another patch may fail loudly on a rebuild; check the release assets when in doubt.
17. **Facebook ships as `arm64-v8a` but decodes via an x86_64 build.** The x86_64 XAPK is downloaded too, only for its `libsuperpack-jni.so` (decoder library for the emulator); the file being patched stays the arm64-v8a one. Don't "simplify" this to a single download or the decoder can't run. The unpacker scripts are fetched at build time; `superpack-ref` in config.toml pins them to a main commit (2026-11-12) because no release ships them yet — drop that line once a HushFacebook release with `scripts/superpack/` is out (then it follows the patches' release tag).

## Conventions

- **CI is the test suite.** Verify scripts with `bash -n build.sh utils.sh` and leave real verification to GitHub Actions. Don't claim a build works without that check (or a runner log).
- **Config is king.** No per-app hard-coding in scripts. A new app means a `[Table]` in `config.toml`, not a code path.
- **Docs travel with changes.** If behavior changes, update `README.md`, `obtainium-import.json` and this file in the same change. Keep releases and the release note changes in mind.
- **Ask before expanding scope.** Do not fix issues #1–#17 above on your own; list them and let the user choose.
- **Plain English in everything the user reads.** No jargon without an explanation.
- Commit messages: only when the user asks for a commit — plain, descriptive.

## Common tasks

### Change an app's version or patches

1. Check the patch bundle's `patches-list.json` for supported versions.
2. Check the download source actually serves the version (for APKPure: the free API, see below).
3. Update `config.toml`; update `README.md` / `obtainium-import.json` / this file if anything user-visible changes.
4. Verify with `bash -n build.sh utils.sh`. The user must push and let CI verify the real build.

APKPure coverage check (the same endpoint apkeep uses):

```
GET https://api.pureapk.com/m/v3/cms/app_version?hl=en-US&package_name=<pkg>
Headers: x-cv: 3172501, x-sv: 29
```

Grep versions with `([a-zA-Z0-9.\-]+):\([0-9a-fA-F]{40,}` (binary protobuf). Caution: newer builds listed on the site are Premium-gated and not served by the free API, and the ChromeOS pseudo-entry (`2000000000.0.0-CrOS`) must be ignored.

### Adding an app

**Only if the user decides to add one.** Checklist:

1. Confirm the patch bundle's `patches-list.json` supports the app and which versions.
2. Confirm the download source (APKPure or official) actually serves a supported arm64-v8a build.
3. Add `[Some-App]` to `config.toml` with `patches-source`, `arch = "arm64-v8a"`, `build-mode = "apk"`; `version = "auto"` unless the patches target a single version, then pin and document why.
4. Watch for a patch-source owner collision: two apps from the same GitHub owner can reuse the first app's cached bundle (`temp/<owner>-rv`).
5. Add a matching entry to `obtainium-import.json` (`apkFilterRegEx` substring of the output filename) and add the app to `README.md` (bold name + link to patch source).
6. Update this file and `CONFIG.md` notes if they reference the app set.

### Troubleshooting a failed build

Read the failing step's log before changing anything:

- "could not get prebuilts" → patch/CLI fetch or picker issue.
- "Could not download" → source/network; for APKPure apps, check the free API coverage.
- `get_patch_last_supported_ver failed` or empty output → CLI output changed or the patch list is unsupported — pin `version` temporarily and tell the user.
- Install/patch step failures → usually a version pin mismatch.
- "superpack-unpack failed" → the x86_64 emulator didn't boot, or the unpacker refused (look for the device decode output: lines starting MISMATCH/UNLISTED/MISSING/REFUSED mean the store didn't match the APK), or the adb/d8/pwsh tooling was missing. The unpacker output goes to the job log.
- If one app failed but others succeeded, the release still publishes — inspect assets and the build log. (Facebook is the exception: if its CI emulator step fails, the job stops before anything builds.)

### Forcing or resetting a rebuild

- **Force a full rebuild:** run the **Build Modules** workflow with `force_all = true`.
- **Reset the state file:** delete `build-state.txt` on the `update` branch deliberately, then run **Build Modules** once — it will re-seed the file. Never edit it by hand.
- The `CI` workflow (cron/manual) has no `force_all` input; don't add one or rewire triggers without the user asking.

## User preferences and history

- The user had Google Photos removed on 2026-11-07 for personal reasons (other apps cover it; releases stayed 3 apps).
- **Facebook was re-added on 2026-11-12 (user decision)** after the HushFacebook maintainer pointed out his `scripts/superpack/` desktop unpacker: APKPure only serves the Android 9+ build, so CI now unpacks it on a temporary x86_64 emulator before patching. The user wants it for the user's uncle (sharp links). The maintainer confirmed a patched unpack works (Home/Reels); the Android 9/10 phone case is untested.
- The user wants every app kept up to date as far as sources allow; temporary pins (Pinterest) are forced by source lag, not taste. **If a pin can be relaxed, tell the user — they will decide.**
- The user's mom uses Truecaller and Pinterest; they should keep working.
- Keep upstream sync **once in a while**, deliberately — agents propose, the user merges.
- Upstream **HushPinterest and HushFacebook are not the user's project** — treat them as third-party sources.
- User notifications: GitHub emails are enough; no other channel needed.
- Repo created 2026-11-04; releases 1–9 as of 2026-11-07, all 9 CI runs green; Facebook added 2026-11-12; sole maintainer **n3thshan**; issues enabled but none open.

## When unsure

Ask the user. Don't guess at version pins, source URLs, signing changes, triggers, or rewires. Small, reviewed steps beat clever automation here.
