# Performance on the DJI RC Plus 2 (Adreno 643)

This document covers the performance work on LibertyRecompAndroid (GTA IV, Xbox 360 static
recompilation) on a **DJI RC Plus 2 Enterprise** controller:

| Component | Specification |
|---|---|
| SoC | Qualcomm QCS5430 |
| CPU | 4× Cortex-A55 1.96 GHz + 3× A78 2.4 GHz + 1× A78 2.7 GHz |
| GPU | **Adreno 643** at 812 MHz |
| Memory | 8 GB RAM |
| OS | Android 11 |
| Screen | 1920×1200, 60 Hz only |

Upstream was developed on an Adreno 650 (Snapdragon 865), which has roughly 1.5× the shader
throughput of this GPU.

**Ground rule: the game is never made to look or play worse.** All measurements use the authors'
default quality (`assets/default_args.txt`). Draw distance, densities, shadows and reflections
were never lowered to gain frames.

## Results

The test spot is a fixed street location, standing in a car in daytime. The frame rate is unlocked
and draw distance is 1.0. The display runs at 60 Hz only, so presented frame times are quantized
to 33, 50 or 67 ms.

| Change | Effect |
|---|---|
| Turnip `TU_DEBUG=` (driver picks GMEM or sysmem per render pass) instead of the app's hard-coded `sysmem` | 17.0 → 19.5 fps (+15 %) |
| Profile-guided optimization of `libmain` and the renderer (upstream's `LIBERTY_ANDROID_PGO` pipeline, profile from ~13 min of driving) | title submit thread −7 % CPU time |
| Cheaper command capture (dirty-range bitset, `memcpy` instead of iterator `insert`, separate `shared_ptr` control blocks) | renderer share of the title thread 50.6 % → 48.2 % (interior) |
| Render-pass merging by attachment borrowing | interior +2 %, street ±0 |
| **Total** | **street ~17 → ~20 fps, interior ~36 fps, identical image** |

Audio: while driving, silent output blocks fell from 300–800 per 1875 (10-second window) to 0–50.
See [STABILITY.md](STABILITY.md#audio-stutter).

## Where the frame time goes

### GPU: ~47–50 ms per street frame
- **G-buffer materials: ~15 ms in total, spread thin.** Live skip tests per pixel shader give these
  costs, against ±1 ms noise:

  | Pixel shader | Draws | Cost | Code (texture fetches / ALU ops) |
  |---|---|---|---|
  | `gta_default_ps2` | 416 | −3 ms | 1 / 16 |
  | `gta_normal_spec_ps2` | — | −2 ms | 3 / 42 |
  | `gta_default_ps4` | — | −1.8 ms | 1 / 34 |
  | trees, `spec_ps2` | — | −1.3 ms | `trees_ps0` 5 / 24 (a deliberate max-dilation art effect) |
  | `gta_default_ps3` | — | −1 ms | 1 / 6 |
  | all others | — | ≤ 1 ms | — |

  Draw counts were not recorded for every shader. Disassembling the original shaders, via
  XenosRecomp to HLSL, shows how small they are, so the cost is MRT write bandwidth and
  rasterization, not shader code. Hand-written overrides have no headroom.
- **Sun shadow map: ~7 ms.** It is about 1470 depth-only draws (no pixel shader) in a single
  render pass into a 1280² map.
- **Deferred lights: ~4 ms.** A hand-optimized light-volume shader would gain at most 1.6 ms.
- **The GPU is bandwidth-bound:** with UBWC disabled (`TU_DEBUG=noubwc`) the frame takes 52 %
  longer. The render target formats are the game's own (RGBA16F HDR, D24FS8 → D32S8), so there is
  nothing to shrink without changing the image.
- **LRZ already works:** Turnip keeps LRZ writes for most of the g-buffer pass. The first draw that
  writes depth with blending turns them off late in the pass, and `nolrz` costs only 2–3 %.

### CPU ceiling: ~41–44 ms per frame
Skipping all material shaders frees about 15 ms of GPU time but only reaches 22.7–24.5 fps. The
title's command submission thread then limits the frame at about 85 % of a core:
- **About half of it is the recompiled game code.**
- **About half is the renderer's command capture** (`ValidateAndCopyCommand`, `CaptureBufferResource`,
  constant deltas). Its self time is dominated by cache misses on recycled ~3 KB command records and
  capture-cache lookups, not by one hot algorithm.
- The other renderer threads each use a large share of a core: the recorder (~75 %), the render
  worker (~65 %) and the game's main thread (~50 %).

### Outlook
Stable 30 fps on the street would need −35 % GPU time and −30 % on three CPU threads at once. A
structural shrink of the command record (several days of work) would lift the CPU ceiling, but it
cannot raise the frame rate while the GPU stays at ~50 ms. On an Adreno 650 controller (e.g. DJI RC
Pro / RM510B, Snapdragon 865) the same build should be substantially faster on the GPU side.

## Measured and rejected

| Idea | Result |
|---|---|
| Qualcomm proprietary Vulkan drivers (AdrenoTools packages) | These report Vulkan 1.1 on this device, so the game refuses them. A v805 driver patched to report 1.3 and expose `shaderInt64` runs the game ([QUALCOMM_DRIVER.md](QUALCOMM_DRIVER.md)) but is not faster than Turnip: 20.2 vs 21.1 fps. |
| `gta4_native_fs_relaxed_precision` (FP16 in pixel shaders) | −10 % on Turnip, and 5.8 % of pixels change |
| `TU_DEBUG=nolrz` | −2–3 % |
| `TU_DEBUG=gmem` / `sysmem` | both worse than automatic per-pass selection |
| Thread pinning (`gta4_thread_pinning` 3/4, manual affinities) | 0 or worse; 4 threads: −35 % |
| Render queue depth (`gta4_native_max_queued_frames` 2/3/4) | 0 |
| `lazy_resolves`, `resolve_swap`, `skip_attachment_barriers` | 0 or worse |
| `gta4_native_shadow_interval=2` | GPU busy 90 → 76 %, but the frame rate barely moved and pacing got worse; also a quality change |
| `gta4_native_protection_lock_spin=8192` (spin before sleeping on the texture-protection lock) | +9 % before PGO, ~+1 % after PGO, and it starved the audio threads. **Default is 0.** |

### The protection-lock spin
An off-CPU profile showed the title thread sleeping about 15 ms per frame on
`queued_protection_mutex_`, which the render worker holds during batch releases. Spinning up to
8192 times before sleeping removed those sleeps and gave +9 % (18.0 → 19.8 fps).

Later, the spinning core turned out to compete with the XMA decoder and the game's audio engine,
and it made the audio-stutter problem worse. After PGO the frame-rate benefit had shrunk to noise
(19.4 vs 19.2 fps), so the cvar is kept but defaults to 0.

## Renderer changes

All renderer changes are in `glue/rexglue-sdk-main/src/graphics/gta4_native/`; the patches live in
`liberty-recomp/patches/`.
- `dirty_state_delta.h`: `BuildRangeSet` marks dirty elements in a stack bitset and reads the runs
  directly, instead of building a vector and sorting it. A host test over 4 million random layouts
  matched the old implementation exactly.
- `stateful_constant_state.h` and `CoalesceStateCommand`: `resize` + `memcpy` instead of
  iterator-range `insert`.
- Buffer and texture resources are created with `new` instead of `make_shared`. Their control block
  then sits on its own cache line, so the title thread's per-draw references no longer bounce lines
  that the recorder reads. `weak_ptr::lock` cost on the title thread: 2.9 → 1.6 % (interior).
- `native_attachment_policy.h`, `BorrowNativeRenderingAttachments`, cvar
  `gta4_native_extend_rendering_scope` (default on): a draw whose attachments are a subset of the
  open scope's reuses that scope, with its own write mask. Interior passes 46 → 31; the g-buffer is
  now one pass instead of one per one or two draws.

## Measurement methods

All measurements were taken over Wi-Fi adb with these methods:
- **FPS and frame times:** `dumpsys SurfaceFlinger --latency` on the game's SurfaceView. Report
  median and p95, never the average alone.
- **GPU load:** `/sys/class/kgsl/kgsl-3d0/gpu_busy_percentage`. GPU time per frame = busy % × frame
  time.
- **Real GPU cost of a pass or shader:** live skip tests. `gta4_native_debug_skip_gpu_range` takes
  `GpuRange` index + 1 (names in `native_performance_samples.cpp`), and
  `gta4_native_skip_pixel_shaders` takes hash prefixes; always keep upstream's default `2673E2AF` in
  the list. Interleave baseline runs between variants. **Do not trust the built-in profiler's
  per-pass milliseconds for small draws**: its timestamp queries inflate them several-fold.
- **CPU:** `simpleperf record --call-graph fp`, both on-CPU and `--trace-offcpu`. Use
  `report --children`, and `report-sample` with a small script to see what is under
  `SubmitTitleCommand`. The renderer `.so` can stay unstripped in the APK for symbols.
- **Pass structure (new diagnostics, off by default):** changing the cvar
  `gta4_native_debug_log_passes` logs two frames as `pass:` lines in logcat:
  - every render pass with its attachments and load/store ops, and every transfer;
  - draw counts per pixel shader (`pass: PS ...`);
  - depth/stencil/blend state histograms (`pass: DS ...`);
  - state-change lines (`pass: D cmd=...`) that map to Turnip's per-pass draw numbers.
- **LRZ decisions:** `TU_DEBUG=perf` makes Turnip log every LRZ disable together with its reason.
- **Capture counters:** the periodic renderer report prints `capture/frame` (draws, buffer
  captures, constant bytes per frame).
- **Live settings:** `files/live_cvars.txt` is re-read when its mtime changes. Write a temporary
  file, `chmod 666` it, then rename it into place, or the game never reads it.
- **Deterministic benchmark:** the game auto-loads the last save, so a restart plus a fixed wait
  gives a repeatable scene without anyone holding the controller.
