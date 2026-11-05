# AGENTS.md

Guidance for AI agents working in this repository. Read this before making any changes.

## What this is

**my-morphe-builder** — a personal, private fork of [j-hc/revanced-magisk-module](https://github.com/j-hc/revanced-magisk-module). It builds patched **Notesnook**, **Google Photos**, **Truecaller**, **Facebook** and **Pinterest** APKs in the cloud with [GitHub Actions](.github/workflows/), using [hxreborn/morphe-patches](https://github.com/hxreborn/morphe-patches) (Notesnook), [Akash-Sriram/morphe-google-photos](https://github.com/Akash-Sriram/morphe-google-photos) (Google Photos, derived from De-Vanced), [heval99/Heval-Morphe-Patches](https://github.com/heval99/Heval-Morphe-Patches) (Truecaller), [SysAdminDoc/Hushfacebook](https://github.com/SysAdminDoc/Hushfacebook) (Facebook) and [SysAdminDoc/HushPinterest](https://github.com/SysAdminDoc/HushPinterest) (Pinterest) with the [Morphe](https://morphe.software) CLI.

The flow: `ci.yml` (daily cron + manual dispatch) → checks whether the newest patch release is newer than what was last built (`--config-update` against `build.md` on the `update` branch) → if so, `build.yml` runs: downloads the stock APK, patches it, signs it, uploads it to a GitHub Release. **Release-only flow** — no Magisk module, no in-app update-check patch, no Telegram notifications.

## Hard constraints (do not violate)

1. **arm64-v8a only.** Never introduce other ABIs (no armeabi-v7a, x86, x86_64, multi-ABI builds) without explicit approval. The Notesnook `arch` is `arm64-v8a` and `utils.sh` refuses bundles without arm64-v8a native libs (`arm64_ok()`).
2. **Bundled `ks.keystore` signs everything.** Do not add per-app key management or secret handling. Patched APKs can't update over official/Play installs; that's accepted.
3. **apkeep/APKPure path stays functional and is the Google Photos, Truecaller, Facebook and Pinterest source.** Don't delete the `apkpure` download source, the apkeep workflow step, or the `arm64_ok` guard. Keep `apkeep -d apk-pure` as apkeep's only download source. Notesnook keeps the official Notesnook endpoint.
4. **Don't bump app `version`s without checking patch support first.** Patches target specific versions - verify the change against the bundle's `patches-list.json` (hxreborn's for Notesnook; Akash-Sriram/morphe-google-photos' for Google Photos, officially `7.99.0.1007655401` only; heval99/Heval-Morphe-Patches' for Truecaller, currently `26.43.5` only; Hushfacebook for Facebook, currently `585.0.0.47.54` only; HushPinterest **v0.0.5** for Pinterest, targets `14.25.0` and `14.38.0` - note the user-pinned `patches-version = "v0.0.5"`: newer releases target builds APKPure doesn't mirror, and `patches-version = "latest"` would fail the download). Google Photos is deliberately pinned to `7.99.0.1012983279` (force-patched with `-f`, patches best-effort); don't change pins blindly - it breaks the build or ships half-patched APKs.
5. **Agent edits files; the user pushes.** No committing/pushing unless the user explicitly asks. No `git remote` operations, no `gh` calls (there is no `gh` here).
6. **Patches-version policy:** `patches-version = "latest"` is intentional. Don't pin it - except **Pinterest**, deliberately pinned to `v0.0.5` by the user (newer HushPinterest releases target Pinterest builds APKPure doesn't mirror; `latest` would download v0.0.13 → targets `14.41.0`, not on APKPure → build fails). Don't "unpin" it until APKPure carries a newer supported build; then re-check and pin the matching pair deliberately.
7. **No scraped/unofficial APK sources** without the user's say-so. Allowed sources are only what's already in `config.toml`/`utils.sh` (`official-dlurl`, `apkpure-dlurl`, `direct-dlurl`, `archive-dlurl`, `apkmirror-dlurl`).

## Repository layout

| Path | Purpose |
|---|---|
| `build.sh` | Entry point: parses config, fetches patch/CLI prebuilts, downloads stock APKs, patches, signs, outputs to `build/` |
| `utils.sh` | All logic: download sources, `get_prebuilts`, `get_patch_last_supported_ver`, APKEditor merge for split bundles, signing, release-changelog assembly |
| `config.toml` | App tables (`[Notesnook]`, `[GooglePhotos]`, `[Truecaller]`, `[Facebook]`, `[Pinterest]`); see `CONFIG.md` |
| `sig.txt` | Allowlist of stock-APK SHA-256 certs; Notesnook is intentionally absent (check is a no-op) |
| `.github/workflows/build.yml` | Build + release flow (Java 21, apkeep fetch, APK merge/patch, `gh release` upload, `update` branch bookkeeping) |
| `.github/workflows/ci.yml` | Daily cron 16:00 UTC + `workflow_dispatch`; decides *whether* to build; then calls `build.yml` |
| `.gitattributes` | LF enforced for text, binary marking for `bin/**`, `*.jar`, `*.keystore`, etc. — do not remove or relax |
| `module/` | Magisk module template — unused in the current `apk`-only build mode; leave alone unless module builds are re-enabled |
| `bin/` | Prebuilt helpers (`apksigner.jar`, `aapt2`, `htmlq`, `tq` TOML parser, `paccer.jar`, `dexlib2.jar`) |
| `.gitignore` | `*.apk`, `*.xapk`, `bin/apkeep`, `temp/`, `build/` |

## Conventions

- **Config is king.** New app = new `[Table]` in `config.toml` + a download source. Nothing hard-coded in scripts. Keep the builder generic.
- **Download source keys** map `DL_SRCS=("direct" "archive" "apkmirror" "apkpure" "official")` to `<src>-dlurl` config keys and `get_<src>_resp|vers|pkg_name`/`dl_<src>` functions in `utils.sh`. Adding a source means touching all three places.
- **Docs travel with changes.** Update `README.md`/`CONFIG.md` when behavior changes. Keep the upstream j-hc README below the `---` in `README.md` for attribution.
- **Commits** are the user's responsibility (see constraint 5). If asked to commit, use plain, descriptive messages and only after `bash -n` passes.
- **CI is the test suite.** There is no Java/jq/toml toolchain expectation on the dev machine — verify with `bash -n build.sh utils.sh` and leave real verification to GitHub Actions. Don't claim the build works without that check (or the runner logs).

## Release flow

1. `ci.yml` wakes (cron 16:00 UTC, or `workflow_dispatch`) → checks out `build.md` **and `build-state.txt`** from `origin/update` → runs `bash ./build.sh config.toml --config-update`.
2. `build-state.txt` is the per-app memory, one line per app: `<table>|<patches-src>|<patches-asset>|<configured-version>`. An app is built only when its patch bundle version, patch source, or configured `version` changed — or when it has no line yet. Fresh repos (no state file) fall back to `build.md`, and unchanged apps are seeded into the state file.
3. `build.yml` runs for the selected apps only (`config.json`), builds, and publishes a new numbered release. Manual "Run workflow" uses the same change detection: if nothing changed, nothing builds. The **force_all** manual input rebuilds everything (and therefore may re-publish unchanged apps).
4. Builds append their source to `temp/built-state.txt`; the update-branch step merges it (plus seeded lines) into `build-state.txt`, replacing only the apps built in that run, then commits `build.md` + `build-state.txt` to the `update` branch.
5. `NEXT_VER_CODE` increments release tags automatically; releases are named `Release` with the changelog notes.
6. "Auto-release on patch updates" is a feature, not an accident: don't rewire triggers; the user wants daily auto-builds.

> **Do not hand-edit `build-state.txt`** on the `update` branch — CI owns it. To force a rebuild, use the force_all manual input; to reset history deliberately, delete the file and the next run re-seeds it.

## Currently in scope

- **Notesnook** — built from the **official** arm64-v8a endpoint (`https://notesnook.com/api/v1/releases/android/latest/arm64-v8a`, a 302 to the official GitHub release asset) via `official-dlurl`.
  - Notesnook on APKPure: 3.4.12/3.4.13/3.4.15 are armeabi-v7a-only — do not switch to it without pinning `version = "3.4.14"` and knowing why.
  - `version = "auto"` is deliberate: highest version supported by the patches. If the official endpoint serves a newer release than the patches support, the patch step fails loudly — expected; wait for a patch update or pin `version`.
- **Google Photos** - built from APKPure via apkeep (`-d apk-pure` only). Version manually pinned to `7.99.0.1012983279`; APKPure serves it as an XAPK with an arm64-v8a-only native split (no v7a/x86), which APKEditor merges into a single APK before patching. MGP v1.17.10 officially targets `7.99.0.1007655401` only, so this build is force-patched (`-f`) and patches are best-effort - check the CI log and the resulting APK before relying on it. The MGP patches rename the package to `app.morphe.android.apps.photos` (GmsCore support, default on) - do not `pkg-name` that; the patches declare `com.google.android.apps.photos` as the input package. When bumping, check MGP's patches-list.json and APKPure availability, then update the pin deliberately.
- **Truecaller** - built from APKPure via apkeep (`-d apk-pure` only) with [heval99/Heval-Morphe-Patches](https://github.com/heval99/Heval-Morphe-Patches). `version = "auto"`: the Truecaller patches target `26.43.5` only, and APKPure serves that version as an XAPK (95.1 MB, listed 2026-11-03) with an arm64-v8a split, which APKEditor merges into a single APK before patching. The patches keep the package name `com.truecaller` (no rename). `auto` follows patch releases - if a future patch release targets a version APKPure doesn't mirror yet, the build fails loudly (expected); wait for APKPure or pin `version`. Check heval99's patches-list.json before any manual version work.
- **Facebook** - built from APKPure via apkeep (`-d apk-pure` only) with [SysAdminDoc/Hushfacebook](https://github.com/SysAdminDoc/Hushfacebook). `version = "auto"`: the Hushfacebook patches target `585.0.0.47.54` only, and APKPure serves that version as an XAPK (129.2 MB, Oct 29 2026); APKEditor merges it into a single APK before patching. The patches keep the package name `com.facebook.katana` (no rename). Upstream's officially tested path is Morphe Manager with the APKMirror .apkm (arm64-v8a, build 476015655, 120-640dpi); this CI build uses APKPure instead, per the user's choice - if the patch step fails, compare against the APKMirror build before assuming a patch bug. The builder auto-includes Hushfacebook's `GmsCore support` patch for apk builds (same as Google Photos), so the patched app routes Google services to MicroG-RE, not Google Play services - the user runs both. `Hushfacebook settings` must stay selected (other patches need it); it is on by default. Note the package conflicts with Meta's own Facebook: patched APK can't install over it (uninstall first, data lost) - accepted. Check Hushfacebook's patches-list.json before any manual version work (main branch can be ahead of the latest release; `patches-version = "latest"` uses the latest *release*, currently v0.20.0).
- **Pinterest** - built from APKPure via apkeep (`-d apk-pure` only) with [SysAdminDoc/HushPinterest](https://github.com/SysAdminDoc/HushPinterest). **User-pinned to `patches-version = "v0.0.5"` and `version = "14.25.0"`** (2026-11-05, user instruction): HushPinterest v0.0.5 (published 2026-10-07) targets Pinterest `14.25.0` (vc 14258020) and `14.38.0` (vc 14388010); APKPure's newest Pinterest is `14.25.0`, and neither 14.41.0 (v0.0.13, latest release) nor 14.43.0 (main, unreleased, needs Manager ≥ 2.4.0) is mirrored there. `auto` would resolve to `14.38.0` → download would fail; `latest` would fetch v0.0.13 → also fail. v0.0.5 has 23 patches and **no** `GmsCore support` / `Fix push notifications` patches (manual: verify APKPure availability before bumping; then pin patch release and Pinterest version together). Package stays `com.pinterest`; sign in with email + password (Google sign-in can't work on a re-signed app). APKEditor merges the XAPK before patching. API check for APKPure coverage: `https://api.pureapk.com/m/v3/cms/app_version?hl=en-US&package_name=<pkg>` (what `apkeep -l` reads; binary protobuf, grep with `([a-zA-Z0-9.\-]+):\([0-9a-fA-F]{40,}`).

## Pitfalls (learn from history)

- **Verify APKPure coverage before wiring an app:** APKPure lags Play Store badly (its Pinterest tops out at 14.25.0 while patches target newer builds). Before adding/bumping an APKPure app, list `https://api.pureapk.com/m/v3/cms/app_version?hl=en-US&package_name=<pkg>` with `x-cv: 3172501` / `x-sv: 29` headers and grep `([a-zA-Z0-9.\-]+):\([0-9a-fA-F]{40,}` (protobuf-ish) - do it before promising a working build.
- **Windows → git → Linux:** files committed from Windows can lose exec bits; workflows call `bash ./build.sh` and `chmod +x bin/*` after checkout. Don't revert those.
- **CRLF:** keep `.gitattributes`. YAML tolerates CRLF, shell scripts don't.
- **Patch releases with extra assets:** heval99 (`SHA256SUMS.txt`, `patches-list.json`, ...) and Hushfacebook (`SHA256SUMS.txt`, `release-receipt-*.json`, ...) ship non-bundle files next to `patches-*.mpp` in their releases. The asset picker in `utils.sh` (`get_prebuilts`) filters out `.asc`/`.json` and now prefers `.mpp` when more than one candidate remains - keep that preference; don't loosen it back to "first one found".
- **hxreborn patch bundles (`.mpp`)** ship `extensions/extension.mpe` and **no** `extensions/shared.*`; the paccer "remove integrations checks" step must skip silently - don't "fix" it to fail on missing files.
- **sig.txt** doesn't include Notesnook; `check_sig` passes through. Don't add entries unless you actually trust stock signatures from that source.
- **APKPure is a third-party mirror** with known malware-distribution history; it's here only for the user's later testing, not for default production use.
- **cmpr helpers are lazy:** `build.sh` downloads the module template's `cmpr` binaries only when at least one *enabled* app builds a module (`build-mode = "module"` or `"both"`). APK-only runs (the norm here) skip them — that's intentional, don't "restore" the unconditional download.

## Common tasks

- **Add a new app:** add `[Some-App]` to `config.toml` with `pkg-name` (for `official-dlurl`) or the source's `*-dlurl`, `patches-source = "owner/repo"`, `arch = "arm64-v8a"` (policy), `build-mode = "apk"`, usually `version = "auto"`. Keep `hidden = true`-ness in mind: config tables build every run. Check the patch bundle's `patches-list.json` first to confirm the app and supported versions. Verify `bash -n` on anything you touch.
- **Change Notesnook version:** only after checking patch targets; update `version` in `config.toml` (and README if it references it); verify arm64-v8a availability in the source.
- **Sync upstream (j-hc/revanced-magisk-module):** carefully, manually — diff against upstream, port fixes (CI, utils.sh bugs), keep our `apkpure`/`official` sources, arm64 guard and arm64-only config; never blind `git merge upstream/main`.
- **Troubleshoot a failed build:** read the failing step's log; distinguish "could not get prebuilts" (patch/CLI fetch or paccer issue), "Could not download" (source/network), "get_patch_last_supported_ver failed" (CLI output changed — fall back to pinning `version`), interpreter/exec errors (exec bits, CRLF).

## Roadmap (as told by the user)

- **Google Photos** was added as the second app (from `Akash-Sriram/morphe-google-photos`); **Truecaller** was added as the third (from `heval99/Heval-Morphe-Patches`); **Facebook** was added as the fourth (from `SysAdminDoc/Hushfacebook`); **Pinterest** was added as the fifth (from `SysAdminDoc/HushPinterest`, pinned to v0.0.5 by the user). More selected apps may be added - chosen apps will be provided later; structure configs to allow it.
- The apkeep path is now used by Google Photos, Truecaller, Facebook and Pinterest (none has an official arm64 direct-download endpoint); Notesnook keeps the official endpoint.
- Upstream syncs are periodic but deliberate — agents propose, the user merges.
- Personal, private project; no template ambitions for now — don't add template scaffolding or public-facing polish.

## When unsure

Ask the user. Don't guess at version pins, source URLs, or CI rewiring. Small, reviewed steps beat clever automation here.
