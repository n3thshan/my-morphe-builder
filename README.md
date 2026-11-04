# my-morphe-builder

Fork of [j-hc/revanced-magisk-module](https://github.com/j-hc/revanced-magisk-module) customized to build a **Notesnook** APK patched with [hxreborn/morphe-patches](https://github.com/hxreborn/morphe-patches) (Unlock pro + Material You theme) using [Morphe](https://morphe.software).

The stock APK is downloaded **from APKPure only**, with [apkeep](https://github.com/EFForg/apkeep) (pinned to v1.1.0 in the workflow, and only ever invoked with `-d apk-pure`). The GitHub Actions workflows build everything in the cloud  -  see [`config.toml`](./config.toml), [`CONFIG.md`](./CONFIG.md) and `.github/workflows/`.

## What it does

* On a daily schedule (or `workflow_dispatch`), the CI checks whether the latest `hxreborn/morphe-patches` release is newer than what was last built.
* If so, it downloads the Notesnook APK/XAPK from APKPure with apkeep (currently `com.streetwriters.notesnook`, version `auto` → highest version supported by the patches, e.g. `3.4.15`), merges the XAPK with APKEditor if needed, patches it with morphe-cli and signs it with the bundled key prebuilt into the repo, then attaches the APK to a GitHub Release.
* **APKPure warning**: [apkeep's docs note APKPure is a third-party APK mirror](https://github.com/EFForg/apkeep/blob/master/USAGE-apkpure.md) which has been caught distributing modified apps, so only use this if you accept that risk. Notesnook is open source, so you can compare its source yourself if you want to be sure.

## Adding more apps later

The builder stays generic  -  future apps need only a new table in [`config.toml`](./config.toml) with their `apkpure-dlurl` (the package id on APKPure) and `patches-source` (any Morphe-patches repo, e.g. another third-party bundle). APKPure remains the only download source used with apkeep.

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
