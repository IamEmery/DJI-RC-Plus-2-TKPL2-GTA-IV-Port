# Stability and audio

## Crashes: a use-after-free race in the title

All crashes seen during several hours of play on the DJI RC Plus 2 have one cause. The main thread
walks an entity's child-object table (`sub_8297CE78` and its callees, reached from `sub_82955F60`).
Meanwhile another title thread frees those children. On the console the timing hid this race; the
faster native renderer exposes it.

Upstream already guards one walk (`GTA4_StaleChildGuard`, the r24 loop). This fork adds the
following.

| Crash site | Fault | Fix |
|---|---|---|
| `sub_8297CE78`, `lwz r28,100(r24)` right after upstream's guard said "readable" | The guest heap page table called the page readable, but the host page was not | `PageReadable` in `gta4-recomp/src/android/android_stale_object_guard.cpp` now confirms with the kernel through `process_vm_readv` (once per cached page, so no measurable cost) |
| `sub_8297AF90`, `lwz r31,60(r30)` | stale child from the table at object+48+648 | hand edit in `generated/gta4_recomp.77.cpp`: `GTA4_StaleObjectReadable(r30+60)`, otherwise the title's "no object" path |
| `sub_8297CE78`, second child-table walk (r27), read at +100 | same race as upstream's r24 walk | hand edit in `generated/gta4_recomp.78.cpp`: the same guard as upstream's, taking the empty-table path |
| `sub_8297CE78`, node walk (r26), `lwz r9,124(r26+48)` | the current node of the scene walk was freed by another thread | hand edit in `generated/gta4_recomp.78.cpp` at `loc_8297D1F8`: if r26..r26+700 is not readable, jump to `loc_8297D490`, where the title ends the walk itself when both cursors meet. Clearing r26 instead would loop forever |
| `sub_8296B0E8` (from `sub_8296E638`), `stvx` to r3+144 | **write** fault on a page that is readable but not writable | **open:** needs the fault address from a crash report |

The generated-code edits are marked `Hand edit (TKPL2)`. They should become entries in upstream's
`tools/apply_generated_patches.py` so that they survive regeneration.

`GTA4_StaleObjectReadable(address, bytes, site)` is a generic helper for further guards. It logs
`stale-object-guard: #N <site> address=...` the first 8 times and then every 1024th time.

### Reading a crash
- The launcher shows a red card after a crash and does not auto-start the game.
- With these patches the report (summary, signal, fault address, backtrace, end of the runtime log)
  is also copied to the app's internal `files/crash_reports/`, which can be read over adb with
  `run-as`. The copy in `Android/data/.../crash_reports` cannot be read without root.
- `adb logcat -b crash` has the native backtrace; map the `libmain.so` pcs with `llvm-objdump` on
  the unstripped build (same BuildId). See [BUILDING.md](BUILDING.md#8-crash-analysis-without-root).
- Android also kills the game's process when the screen turns off ("excessive cpu" in the
  background). That is not a crash: the launcher does not treat it as one and auto-starts normally.

### Hangs
One hang was seen and did not reproduce: all renderer threads were in futex waits, the GPU was
idle, and nothing was logged. Debuggers cannot attach without root on this device, and the NDK's
host lldb needs its bundled Python (`lldb.sh`). The way to get stacks is:
- run simpleperf with `--trace-offcpu --call-graph fp`;
- briefly `SIGSTOP` / `SIGCONT` the game through `run-as`, so that every sleeping thread wakes and
  leaves an off-CPU sample with its call chain.

## Audio stutter

**Symptom:** while driving through busy streets, the sound broke up. The audio driver logs every
10 s whenever it had to play silence:
`audio: N of 1875 blocks were silence (no guest frame ready)`. Here N was 300–800, a quarter to a
third of all output.

**Cause:** an off-CPU profile showed the chain.
- The SDL audio callback waits for frames. The Audio Worker runs the title's callback, which waits
  on the title's audio engine thread.
- That engine thread spent about half its time blocked inside `XmaDecoder::WriteRegister`: every
  XMA context kick waits (`WaitForWorkDone`) until the **single** XMA decoder thread has decoded
  it.
- The decoder thread often ran on a Cortex-A55, and it competed with four busy render threads for
  the big cores. The protection-lock spin, enabled at the time, used up one more big core.

**Fix** (`glue/rexglue-sdk-main/src/audio/xma_decoder.cpp`):
- The XMA decoder thread is pinned to every core faster than the slowest cluster (logged as
  `audio-affinity xma_decoder cores=4`).
- The guest thread that kicks XMA contexts gets the Android audio priority, `setpriority(-16)`, the
  first time it kicks (logged as `audio-priority guest-audio-engine`).
- `gta4_native_protection_lock_spin` defaults to 0 (see [PERFORMANCE.md](PERFORMANCE.md)).

**Result:** while driving, N fell from 300–800 to 0–50 per 10 s, and is mostly 0. The frame rate did
not change measurably.

### Round 2: short dropouts

**Symptom:** after the fix above, driving with the radio on and shooting still crackled: N was
30–180 per 10 s.

**Diagnosis.** Two counters were added to see the shape of the gaps. The driver's line now ends
with `; R runs, longest L blocks, min depth D`, and the Audio Worker logs
`audio-producer: C callbacks, E without a frame, slowest S us, longest gap G us` every 10 s.
They showed 25–135 separate runs of only 2–3 blocks (10–16 ms) per 10 s, the queue dropping to
depth 1, no callback ever returning without a frame, but the slowest callback taking 17–27 ms for
a 5.3 ms block. An off-CPU profile (`simpleperf record --app com.libertyrecomp --trace-offcpu`;
plain shell `simpleperf` is denied `perf_event_open` on this firmware) of the engine thread, the
XMA decoder and the SDL audio thread found no wait longer than 15 ms in 40 s. So nothing stalls:
the title's audio engine thread is simply CPU-bound, at 50–72 % of a big core on average with
peaks over 100 %, and every slow block costs the output queue its lead.

Two host-side losses on that thread were measurable:
- `XAudioGetVoiceCategoryVolumeChangeMask` (called once per block, 180/s) did
  `Sleep(1 us)`, which on Android takes 0.2–0.3 ms with timer slack: 5 % of the thread's time.
- The thread floated over the four big cores; the prime core runs at 2.7 GHz against 2.4 GHz for
  the other three.

**Fix:**
- `src/kernel/xboxkrnl/xboxkrnl_audio.cpp`: the sleep becomes `MaybeYield()`, as in xenia.
- `src/audio/xma_decoder.cpp`: the engine thread is pinned to the cores with the highest
  `cpuinfo_max_freq` the first time it kicks XMA (cvar `audio_engine_prime_core`, default on;
  logged as `audio-affinity guest-audio-engine cores=1`).

**Result:** over three minutes of the same driving and shooting, 15 of 18 ten-second periods had no
silence at all; the other three had 31, 1 and 2 blocks (before: 30–180 in most periods). The
queue now stays 18–32 frames deep. The slowest callback is unchanged (20–26 ms), so a heavier
mix could still run short; the counters above show it if so.

Not related to the game: the audio HAL logs `out_write: underrun` every 5–10 s (a ~4 ms gap in
AudioFlinger's fast mixer). SDL's own `Audio playback underflow` never fires, so the app always
delivered its data in time; this is left as is.

## Launcher auto-start
`LauncherActivity` starts the game on its own 1.5 s after launch, under these conditions:
- the game is installed;
- the newest crash report is not a new native crash, Java crash or ANR. `CrashReports.lastSessionCrashed()`
  decides this from the newest saved report, because the launcher's `onResume` collects reports
  concurrently.

Any touch or key during those 1.5 s keeps the launcher open, for example to change the driver.
Development scripts can still pass `--ez play true` to start the game immediately.
