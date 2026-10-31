# DJI RC Plus 2 (TKPL2) GTA IV Port

Grand Theft Auto IV (Xbox 360, statically recompiled) running natively on a
**DJI RC Plus 2 Enterprise** drone remote controller: Qualcomm QCS5430, Adreno 643,
Android 11. It is played with the controller's own sticks, wheels and buttons.

This repository is a set of patches and documentation on top of
[LibertyRecompAndroid](https://github.com/vaduur/LibertyRecompAndroid) v0.5.9.3, the Android port of
[Liberty Recompiled](https://github.com/OZORDI/LibertyRecomp).
**It contains no game files.** You need your own legally obtained disc image of GTA IV and Title
Update 8.

The controller-side work is in the companion repository
[DJI RC Plus 2 (TKPL2) Native Gamepad Bridge for Gaming](https://github.com/iamemery/DJI-RC-Plus-2-TKPL2-Native-Gamepad-Bridge-for-Gaming):
- the DUML protocol;
- the reusable `djirc` input library;
- a tester app for every stick, wheel and button.

## What the patches add

| Patch | What it does | Result on the RC |
|---|---|---|
| `0001-dji-rc-plus2-controls` | The RC's sticks, wheels and buttons as an SDL gamepad, read over DUML; the top buttons arrive as F1–F6 | all controls work in game ([layout](docs/GTA4_CONTROLS.md)) |
| `0002-launcher-autostart-and-crash-reports` | The game starts by itself unless the last session crashed; crash reports readable over adb | verified on the RC |
| `0003-stale-object-guards` | Guards against a title-side use-after-free race in the entity walk | four crash sites fixed ([details](docs/STABILITY.md)) |
| `0004-xma-decoder-scheduling` | XMA audio decoder kept off the slow cores; the game's audio engine at audio priority | audio dropouts while driving 300–800 → 0–50 blocks per 10 s |
| `0005-renderer-optimizations-and-diagnostics` | Render-pass merging, cheaper command capture, an optional lock spin (default off), pass and state diagnostics | see [PERFORMANCE.md](docs/PERFORMANCE.md) |
| `0006-vulkan-proxy-qualcomm-shaderint64` | Research: `shaderInt64` on one proprietary Qualcomm driver build; inactive with Turnip | see [QUALCOMM_DRIVER.md](docs/QUALCOMM_DRIVER.md) |

## Status

| Area | State |
|---|---|
| Playable with the RC's controls | yes |
| Frame rate (authors' default quality, no reductions) | ~20 fps on the street (was ~17), ~36 fps indoors |
| What limits it | the GPU (~47–50 ms per street frame, bandwidth-bound); then the title's submit thread (~41–44 ms) |
| Audio | stable after patch 0004 |
| Stability | known race guarded at four sites; one open write fault ([STABILITY.md](docs/STABILITY.md)) |
| Input rate | 10 Hz, set by the DJI service; the RC's USB gamepad reports ~63 Hz but Android does not deliver its events ([details](docs/GTA4_CONTROLS.md#input-rate)) |

All performance work followed one rule: **no quality reductions.** Draw distance, densities and
shadows stay at the port authors' defaults. [PERFORMANCE.md](docs/PERFORMANCE.md) lists what was
measured, including the ideas that did not help.

## Quick start

1. Get ADB access to the controller ([HARDWARE.md](docs/HARDWARE.md)).
2. Build LibertyRecompAndroid v0.5.9.3 with `liberty-recomp/patches/`
   ([BUILDING.md](docs/BUILDING.md); profile-guided optimization recommended).
3. Install the APK. Put your disc image and Title Update 8 into
   `Android/data/com.libertyrecomp/files/install/` and install them from the launcher.
4. In `Android/data/com.libertyrecomp/files/env.txt`, set `TU_DEBUG=` (empty). That lets Turnip
   choose GMEM or sysmem per render pass, which is 15 % faster on the Adreno 643 than the app's
   default.

## Repository layout

```
liberty-recomp/patches/   patches against LibertyRecompAndroid v0.5.9.3
liberty-recomp/README.md  base revision, how to apply, notes
docs/BUILDING.md          full source build on macOS, PGO, staging, device configuration, crash analysis
docs/PERFORMANCE.md       measurements, where the frame time goes, what helped and what did not
docs/STABILITY.md         crash analysis and guards, hangs, the audio stutter fix, launcher auto-start
docs/GTA4_CONTROLS.md     how the RC maps to the Xbox 360 pad in GTA IV
docs/QUALCOMM_DRIVER.md   research: running the proprietary Adreno driver
docs/HARDWARE.md          the controller, ADB access, security notes
tools/                    frame-rate and driver A/B scripts used for the measurements
```

## License

This repository is GPL-3.0 ([LICENSE](LICENSE)): the patches modify LibertyRecompAndroid, which is
GPL-3.0. GTA IV is a trademark of Rockstar Games; this project is not affiliated with Rockstar
Games, Take-Two Interactive or DJI.
