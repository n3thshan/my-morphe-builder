# my-morphe-builder

Fork of [j-hc/revanced-magisk-module](https://github.com/j-hc/revanced-magisk-module) customized to build **Notesnook** and **Google Photos** APKs patched with [hxreborn/morphe-patches](https://github.com/hxreborn/morphe-patches) (Notesnook) and [Akash-Sriram/morphe-google-photos](https://github.com/Akash-Sriram/morphe-google-photos) (Google Photos) using [Morphe](https://morphe.software).

Stock APKs come from the **official Notesnook endpoint** (`notesnook.com/api/v1/releases/android/latest/arm64-v8a`) and from **APKPure via [apkeep](https://github.com/EFForg/apkeep)** for Google Photos. The GitHub Actions workflows build everything in the cloud  -  see [`config.toml`](./config.toml), [`CONFIG.md`](./CONFIG.md) and `.github/workflows/`.

## What it does

* On a daily schedule (or manual dispatch), the CI compares each app's patch bundle version **and pinned version** against a per-app state file (`build-state.txt` on the `update` branch) and builds only apps that actually changed. Releases therefore contain only updated apps — no redundant same-version APKs. Manual runs are change-based too; the **force_all** option rebuilds everything.
* If so, it builds and attaches the patched APKs to a GitHub Release:
  * **Notesnook**  -  the **official arm64-v8a APK** from `notesnook.com/api/v1/releases/android/latest/arm64-v8a` (a 302 redirect to the official GitHub release asset) via `official-dlurl`. **Note**: the official endpoint always serves the newest release; if Notesnook ships a version newer than the patches support, the build fails loudly at the patch step (expected  -  wait for a patches update or pin `version` in [`config.toml`](./config.toml)).
  * **Google Photos**  -  via [apkeep](https://github.com/EFForg/apkeep) from APKPure (`-d apk-pure` only, pinned to the latest apkeep release in the workflow). Version pinned to `7.99.0.1012983279`, which APKPure serves as an XAPK with an arm64-v8a-only native split; APKEditor merges it into a single APK before patching. **Note**: MGP v1.17.10 officially targets `7.99.0.1007655401` only - this newer build is force-patched (`-f`), so patches are best-effort. Bump the pin deliberately, after checking MGP's `patches-list.json`.
* **arm64-v8a only.** The project does not support other ABIs. Notesnook's official build is already arm64-v8a-only; Google Photos comes as a universal APK and the patch step strips everything except arm64-v8a.
* **APKPure warning**: the Google Photos build downloads its stock APK from APKPure. [apkeep's docs note APKPure is a third-party APK mirror](https://github.com/EFForg/apkeep/blob/master/USAGE-apkpure.md) which has been caught distributing modified apps, so only use it if you accept that risk.

## Obtainium

[![Get it on Obtainium](https://wispydocs.pages.dev/images/badge_obtainium.png)](./obtainium-import.json)

Import [`obtainium-import.json`](./obtainium-import.json) via Obtainium's **Import/Export -> Import from file**. It adds both **Notesnook** (`com.streetwriters.notesnook`) and **Google Photos** (`app.morphe.android.apps.photos`), tracks the GitHub Releases created by this project's CI with per-app asset filters (`notesnook` / `google-photos`), and has `settings: null` so your Obtainium preferences are untouched.

## Adding more apps later

The builder stays generic  -  future apps need only a new table in [`config.toml`](./config.toml) with a download source (`official-dlurl` / `direct-dlurl` / `apkpure-dlurl` for apkeep) and `patches-source` (any Morphe-patches repo, e.g. another third-party bundle). The apkeep path uses APKPure only. Apps configured with `version = "auto"` follow the patches; everything else is pinned.

## Using your own fork

1. Push this repository to GitHub.
2. Make sure GitHub Actions are enabled for the repository.
3. Run the **Build Modules** workflow (or wait for the daily cron).
4. Grab the patched APK from the new release.

---

# Upstream original README

# ReVanced Magisk Module
[![CI](https://github.com/j-hc/revanced-magisk-module/actions/workflows/ci.yml/badge.svg?event=schedule)](https://github.com/j-hc/revanced-magisk-module/actions/workflows/ci.yml)


Extensive ReVanced builder  

Get the [latest CI release](https://github.com/j-hc/revanced-magisk-module/releases).

Use [**zygisk-detach**](https://github.com/j-hc/zygisk-detach) to detach YouTube and YT Music from Play Store if you are using magisk modules. 

<details><summary><big>Features</big></summary>
<ul>
 <li> Supports all present and future ReVanced apps (including projects implementing the same interface like Morphe)</li>
 <li> Receives in-app updates</li>
 <li> Can build modules and non-root APKs</li>
 <li> Updated daily with the latest versions of apps and patches</li>
 <li> Optimizes APKs and modules for size</li>
 <li> Modules</li>
    <ul>
     <li> handle installation of the correct version of the stock app and all that</li>
     <li> do not trigger root detections</li>
     <li> receive updates from Magisk/KernelSU app</li>
     <li> recompile invalidated odex for faster usage</li>
    </ul>
</ul>
</details>

## To include/exclude patches or patch other apps

 * Star the repo :eyes:
 * Use the repo as a [template](https://github.com/new?template_name=revanced-magisk-module&template_owner=j-hc)
 * Customize [`config.toml`](./config.toml) using [rvmm-config-gen](https://j-hc.github.io/rvmm-config-gen/)
 * Run the build [workflow](../../actions/workflows/build.yml)
 * Grab your modules and APKs from [releases](../../releases)

also see here [`CONFIG.md`](./CONFIG.md)

## If you are having trouble with the classic mount method of the modules
such as,
- **"Reflash needed"** error after reboots
- **"Suspicious mount detected"** warnings from root detector apps

You can consider using [rvmm-zygisk-mount](https://github.com/j-hc/rvmm-zygisk-mount)

## Building Locally
### On Termux
```console
bash <(curl -sSf https://raw.githubusercontent.com/j-hc/revanced-magisk-module/main/build-termux.sh)
```

### On Linux
```console
$ git clone https://github.com/j-hc/revanced-magisk-module --depth 1
$ cd revanced-magisk-module
$ ./build.sh
```
