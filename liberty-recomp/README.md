# Patches for LibertyRecompAndroid

Base: [vaduur/LibertyRecompAndroid](https://github.com/vaduur/LibertyRecompAndroid)
tag `v0.5.9.3` (commit `e6a8b0a`, plus the README-only commit `f4f6d8a`), with
submodules initialized and `tools/setup_repo.py --prepare-only` run.

```
git clone --recurse-submodules https://github.com/vaduur/LibertyRecompAndroid
cd LibertyRecompAndroid && git checkout v0.5.9.3
python3 tools/setup_repo.py --prepare-only      # Python 3.10+
git apply /path/to/liberty-recomp/patches/*.patch
```

Then build as described in [docs/BUILDING.md](../docs/BUILDING.md).

| Patch | What it does | Measured |
|---|---|---|
| `0001-dji-rc-plus2-controls` | `DjiRcJoystickHandler`: the RC's sticks, wheels and buttons as an SDL gamepad (DUML on 127.0.0.1:40007 + F1-F6 keys); `LibertyActivity` installs it and forwards the top row. | all controls work in game; see [GTA4_CONTROLS.md](../docs/GTA4_CONTROLS.md) |
| `0002-launcher-autostart-and-crash-reports` | The launcher starts the game after 1.5 s (a touch or key cancels) unless the last session crashed; crash reports are also kept in app-internal storage. | verified both paths on the RC |
| `0003-stale-object-guards` | Confirms "readable" guest pages with `process_vm_readv` before the game walks freed entity objects, and adds two more guards in the same family of game functions. | four crashes in `sub_8297xxxx` fixed |
| `0004-xma-decoder-scheduling` | Keeps the XMA audio decoder off the slowest CPU cluster, raises the priority of the guest audio engine thread and pins it to the prime core; replaces a per-block `Sleep(1 us)` in `XAudioGetVoiceCategoryVolumeChangeMask` with a yield; adds the gap-shape and producer counters. | silent audio blocks while driving: 300-800 -> 0-50 -> mostly 0 per 1875 |
| `0005-renderer-optimizations-and-diagnostics` | Render-pass merging by borrowing attachments, faster constant deltas, cheaper resource allocation, an optional spin-before-sleep on the texture-protection lock (`gta4_native_protection_lock_spin`, default 0), `REX_DIAGNOSTICS_DIR` for the GPU profiler export, and off-by-default pass logging. | indoors +2%, street unchanged at equal quality; details in [PERFORMANCE.md](../docs/PERFORMANCE.md) |
| `0006-vulkan-proxy-qualcomm-shaderint64` | Lets the Vulkan proxy expose `shaderInt64` on one specific Qualcomm driver build (research, inactive with Turnip). | see [QUALCOMM_DRIVER.md](../docs/QUALCOMM_DRIVER.md) |

## Notes

- `0003` edits files under `gta4-recomp/generated/`. Regenerating the
  recompiled code drops those edits; upstream they belong in the generated-code
  patch list.
- Not included: a local workaround that removed three Bink shader overrides
  from `LibertyRecompLib/shader_overrides/manifest.json` because the bundled
  macOS `dxc` crashed on them. Builds on Linux/Windows do not need it.
- The PGO profile used for the measured builds is device-specific and is not
  part of this repository; [BUILDING.md](../docs/BUILDING.md) explains how to
  record one.
- These patches are GPL-3.0, like LibertyRecompAndroid ([LICENSE](LICENSE)).
