# my-morphe-builder

Fork of [j-hc/revanced-magisk-module](https://github.com/j-hc/revanced-magisk-module) customized to build a **Notesnook** APK patched with [hxreborn/morphe-patches](https://github.com/hxreborn/morphe-patches) (Unlock pro + Material You theme) using [Morphe](https://morphe.software).

The stock APK is downloaded **from the official Notesnook site** (`notesnook.com/api/v1/releases/android/latest/arm64-v8a`). The [apkeep](https://github.com/EFForg/apkeep)-based APKPure path is kept in the repo for later testing but unused. The GitHub Actions workflows build everything in the cloud  -  see [`config.toml`](./config.toml), [`CONFIG.md`](./CONFIG.md) and `.github/workflows/`.

## What it does

* On a daily schedule (or `workflow_dispatch`), the CI checks whether the latest `hxreborn/morphe-patches` release is newer than what was last built.
* If so, it downloads the **official arm64-v8a APK** from `notesnook.com/api/v1/releases/android/latest/arm64-v8a` (a 302 redirect to the official GitHub release asset) with the builder's `official-dlurl` support, patches it with morphe-cli and signs it with the bundled key prebuilt into the repo, then attaches the APK to a GitHub Release. The apkeep/APKPure path is kept in the repo for later testing but is not used.
* **Note**: the official endpoint always serves the newest release; if Notesnook ships a version newer than the patches support, the build fails loudly at the patch step (expected — wait for a patches update or pin `version` in [`config.toml`](./config.toml)).
* **arm64-v8a only.** The project does not support other ABIs. The official APK is already arm64-v8a-only; the available APKPure XAPKs (3.4.12/3.4.13/3.4.15) are 32-bit-only, which is why the official endpoint is the default source.
* **APKPure warning** (if you switch to the apkeep source): [apkeep's docs note APKPure is a third-party APK mirror](https://github.com/EFForg/apkeep/blob/master/USAGE-apkpure.md) which has been caught distributing modified apps, so only use it if you accept that risk.

## Obtainium

[<img width="566" height="170" alt="badge_obtainium" src="https://github.com/user-attachments/assets/62dc64cd-084d-48ee-9f40-8c282ae8b787" />](obtainium://apps/%5B%7B%22additionalSettings%22%3A%22%7B%5C%22includePrereleases%5C%22%3Afalse%2C%5C%22fallbackToOlderReleases%5C%22%3Atrue%2C%5C%22filterReleaseTitlesByRegEx%5C%22%3A%5C%22%5C%22%2C%5C%22filterReleaseNotesByRegEx%5C%22%3A%5C%22%5C%22%2C%5C%22verifyLatestTag%5C%22%3Afalse%2C%5C%22sortMethodChoice%5C%22%3A%5C%22date%5C%22%2C%5C%22useLatestAssetDateAsReleaseDate%5C%22%3Afalse%2C%5C%22releaseTitleAsVersion%5C%22%3Afalse%2C%5C%22trackOnly%5C%22%3Afalse%2C%5C%22versionExtractionRegEx%5C%22%3A%5C%22%5C%22%2C%5C%22matchGroupToUse%5C%22%3A%5C%22%5C%22%2C%5C%22versionDetection%5C%22%3Atrue%2C%5C%22releaseDateAsVersion%5C%22%3Afalse%2C%5C%22useVersionCodeAsOSVersion%5C%22%3Afalse%2C%5C%22apkFilterRegEx%5C%22%3A%5C%22notesnook%5C%22%2C%5C%22invertAPKFilter%5C%22%3Afalse%2C%5C%22autoApkFilterByArch%5C%22%3Atrue%2C%5C%22appName%5C%22%3A%5C%22%5C%22%2C%5C%22appAuthor%5C%22%3A%5C%22%5C%22%2C%5C%22shizukuPretendToBeGooglePlay%5C%22%3Afalse%2C%5C%22allowInsecure%5C%22%3Afalse%2C%5C%22exemptFromBackgroundUpdates%5C%22%3Afalse%2C%5C%22skipUpdateNotifications%5C%22%3Afalse%2C%5C%22about%5C%22%3A%5C%22%5C%22%2C%5C%22refreshBeforeDownload%5C%22%3Afalse%2C%5C%22includeZips%5C%22%3Afalse%2C%5C%22zippedApkFilterRegEx%5C%22%3A%5C%22%5C%22%7D%22%2C%22author%22%3A%22n3thshan%22%2C%22id%22%3A%22com.streetwriters.notesnook%22%2C%22name%22%3A%22Notesnook%22%2C%22url%22%3A%22https%3A%2F%2Fgithub.com%2Fn3thshan%2Fmy-morphe-builder%22%7D%5D)

With [Obtainium](https://github.com/ImranR98/Obtainium) installed on your device, tap the badge to add this repository's Notesnook builds with a single click. Obtainium then installs and auto-updates the APK from the GitHub Releases created by this project's CI (asset filter `notesnook`, arch matched automatically, including older compatible releases as fallback).

## Adding more apps later

The builder stays generic  -  future apps need only a new table in [`config.toml`](./config.toml) with a download source (`official-dlurl` / `direct-dlurl` / `apkpure-dlurl` for apkeep) and `patches-source` (any Morphe-patches repo, e.g. another third-party bundle). The apkeep path uses APKPure only.

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
