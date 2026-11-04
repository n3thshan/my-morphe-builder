# my-morphe-builder

Fork of [j-hc/revanced-magisk-module](https://github.com/j-hc/revanced-magisk-module) customized to build a **Notesnook** APK patched with [hxreborn/morphe-patches](https://github.com/hxreborn/morphe-patches) (Unlock pro + Material You theme) using [Morphe](https://morphe.software).

The stock APK is downloaded **from the official Notesnook site** (`notesnook.com/api/v1/releases/android/latest/arm64-v8a`). The [apkeep](https://github.com/EFForg/apkeep)-based APKPure path is kept in the repo for later testing but unused. The GitHub Actions workflows build everything in the cloud  -  see [`config.toml`](./config.toml), [`CONFIG.md`](./CONFIG.md) and `.github/workflows/`.

## What it does

* On a daily schedule (or `workflow_dispatch`), the CI checks whether the latest `hxreborn/morphe-patches` release is newer than what was last built.
* If so, it downloads the **official arm64-v8a APK** from `notesnook.com/api/v1/releases/android/latest/arm64-v8a` (a 302 redirect to the official GitHub release asset) with the builder's `official-dlurl` support, patches it with morphe-cli and signs it with the bundled key prebuilt into the repo, then attaches the APK to a GitHub Release. The apkeep/APKPure path is kept in the repo for later testing but is not used.
* **Note**: the official endpoint always serves the newest release; if Notesnook ships a version newer than the patches support, the build fails loudly at the patch step (expected — wait for a patches update or pin `version` in [`config.toml`](./config.toml)).
* **arm64-v8a only.** The project does not support other ABIs. The official APK is already arm64-v8a-only; the available APKPure XAPKs (3.4.12/3.4.13/3.4.15) are 32-bit-only, which is why the official endpoint is the default source.
* **APKPure warning** (if you switch to the apkeep source): [apkeep's docs note APKPure is a third-party APK mirror](https://github.com/EFForg/apkeep/blob/master/USAGE-apkpure.md) which has been caught distributing modified apps, so only use it if you accept that risk.

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
