# AGENTS.md

Guidance for AI agents working in this repository. Read this before making any changes.

## What this is

**my-morphe-builder** — a personal, private fork of [j-hc/revanced-magisk-module](https://github.com/j-hc/revanced-magisk-module). It builds patched **Notesnook** and **Google Photos** APKs in the cloud with [GitHub Actions](.github/workflows/), using [hxreborn/morphe-patches](https://github.com/hxreborn/morphe-patches) (Notesnook) and [Akash-Sriram/morphe-google-photos](https://github.com/Akash-Sriram/morphe-google-photos) (Google Photos, derived from De-Vanced) with the [Morphe](https://morphe.software) CLI.

The flow: `ci.yml` (daily cron + manual dispatch) → checks whether the newest patch release is newer than what was last built (`--config-update` against `build.md` on the `update` branch) → if so, `build.yml` runs: downloads the stock APK, patches it, signs it, uploads it to a GitHub Release. **Release-only flow** — no Magisk module, no in-app update-check patch, no Telegram notifications.

## Hard constraints (do not violate)

1. **arm64-v8a only.** Never introduce other ABIs (no armeabi-v7a, x86, x86_64, multi-ABI builds) without explicit approval. The Notesnook `arch` is `arm64-v8a` and `utils.sh` refuses bundles without arm64-v8a native libs (`arm64_ok()`).
2. **Bundled `ks.keystore` signs everything.** Do not add per-app key management or secret handling. Patched APKs can't update over official/Play installs; that's accepted.
3. **apkeep/APKPure path stays functional and is the Google Photos source.** Don't delete the `apkpure` download source, the apkeep workflow step, or the `arm64_ok` guard. Keep `apkeep -d apk-pure` as apkeep's only download source. Notesnook keeps the official Notesnook endpoint.
4. **Don't bump app `version`s without checking patch support first.** Patches target specific versions - verify the change against the bundle's `patches-list.json` (hxreborn's for Notesnook; Akash-Sriram/morphe-google-photos' for Google Photos, officially `7.99.0.1007655401` only). Google Photos is deliberately pinned to `7.99.0.1012983279` (force-patched with `-f`, patches best-effort); don't change pins blindly - it breaks the build or ships half-patched APKs.
5. **Agent edits files; the user pushes.** No committing/pushing unless the user explicitly asks. No `git remote` operations, no `gh` calls (there is no `gh` here).
6. **Patches-version policy:** `patches-version = "latest"` is intentional. Don't pin it.
7. **No scraped/unofficial APK sources** without the user's say-so. Allowed sources are only what's already in `config.toml`/`utils.sh` (`official-dlurl`, `apkpure-dlurl`, `direct-dlurl`, `archive-dlurl`, `apkmirror-dlurl`).

## Repository layout

| Path | Purpose |
|---|---|
| `build.sh` | Entry point: parses config, fetches patch/CLI prebuilts, downloads stock APKs, patches, signs, outputs to `build/` |
| `utils.sh` | All logic: download sources, `get_prebuilts`, `get_patch_last_supported_ver`, APKEditor merge for split bundles, signing, release-changelog assembly |
| `config.toml` | App tables (currently only `[Notesnook]`); see `CONFIG.md` |
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

1. `ci.yml` wakes (cron 16:00 UTC, or `workflow_dispatch`) → `should_build` job runs `bash ./build.sh config.toml --config-update`.
2. If the newest patch release isn't already in `build.md` (on `origin/update`) → `build.yml` runs → builds → `gh release create/edit` with `./build/*`.
3. `build.md` is written during the build and committed to the `update` branch; the daily job compares against it to avoid redundant builds.
4. `NEXT_VER_CODE` increments release tags automatically; releases are named `Release` with the changelog notes.
5. "Auto-release on patch updates" is a feature, not an accident: don't rewire triggers; the user wants daily auto-builds.

## Currently in scope

- **Notesnook** — built from the **official** arm64-v8a endpoint (`https://notesnook.com/api/v1/releases/android/latest/arm64-v8a`, a 302 to the official GitHub release asset) via `official-dlurl`.
  - Notesnook on APKPure: 3.4.12/3.4.13/3.4.15 are armeabi-v7a-only — do not switch to it without pinning `version = "3.4.14"` and knowing why.
  - `version = "auto"` is deliberate: highest version supported by the patches. If the official endpoint serves a newer release than the patches support, the patch step fails loudly — expected; wait for a patch update or pin `version`.
- **Google Photos** - built from APKPure via apkeep (`-d apk-pure` only). Version manually pinned to `7.99.0.1012983279`; APKPure serves it as an XAPK with an arm64-v8a-only native split (no v7a/x86), which APKEditor merges into a single APK before patching. MGP v1.17.10 officially targets `7.99.0.1007655401` only, so this build is force-patched (`-f`) and patches are best-effort - check the CI log and the resulting APK before relying on it. The MGP patches rename the package to `app.morphe.android.apps.photos` (GmsCore support, default on) - do not `pkg-name` that; the patches declare `com.google.android.apps.photos` as the input package. When bumping, check MGP's patches-list.json and APKPure availability, then update the pin deliberately.

## Pitfalls (learn from history)

- **Windows → git → Linux:** files committed from Windows can lose exec bits; workflows call `bash ./build.sh` and `chmod +x bin/*` after checkout. Don't revert those.
- **CRLF:** keep `.gitattributes`. YAML tolerates CRLF, shell scripts don't.
- **hxreborn patch bundles (`.mpp`)** ship `extensions/extension.mpe` and **no** `extensions/shared.*`; the paccer "remove integrations checks" step must skip silently — don't "fix" it to fail on missing files.
- **sig.txt** doesn't include Notesnook; `check_sig` passes through. Don't add entries unless you actually trust stock signatures from that source.
- **APKPure is a third-party mirror** with known malware-distribution history; it's here only for the user's later testing, not for default production use.

## Common tasks

- **Add a new app:** add `[Some-App]` to `config.toml` with `pkg-name` (for `official-dlurl`) or the source's `*-dlurl`, `patches-source = "owner/repo"`, `arch = "arm64-v8a"` (policy), `build-mode = "apk"`, usually `version = "auto"`. Keep `hidden = true`-ness in mind: config tables build every run. Check the patch bundle's `patches-list.json` first to confirm the app and supported versions. Verify `bash -n` on anything you touch.
- **Change Notesnook version:** only after checking patch targets; update `version` in `config.toml` (and README if it references it); verify arm64-v8a availability in the source.
- **Sync upstream (j-hc/revanced-magisk-module):** carefully, manually — diff against upstream, port fixes (CI, utils.sh bugs), keep our `apkpure`/`official` sources, arm64 guard and arm64-only config; never blind `git merge upstream/main`.
- **Troubleshoot a failed build:** read the failing step's log; distinguish "could not get prebuilts" (patch/CLI fetch or paccer issue), "Could not download" (source/network), "get_patch_last_supported_ver failed" (CLI output changed — fall back to pinning `version`), interpreter/exec errors (exec bits, CRLF).

## Roadmap (as told by the user)

- **Google Photos** was added as the second app (from `Akash-Sriram/morphe-google-photos`). More selected apps may be added — chosen apps will be provided later; structure configs to allow it.
- The apkeep path is now used by Google Photos (Google Photos has no official arm64 direct-download endpoint); Notesnook keeps the official endpoint.
- Upstream syncs are periodic but deliberate — agents propose, the user merges.
- Personal, private project; no template ambitions for now — don't add template scaffolding or public-facing polish.

## When unsure

Ask the user. Don't guess at version pins, source URLs, or CI rewiring. Small, reviewed steps beat clever automation here.
