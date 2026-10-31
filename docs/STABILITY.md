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

## Launcher auto-start
`LauncherActivity` starts the game on its own 1.5 s after launch, under these conditions:
- the game is installed;
- the newest crash report is not a new native crash, Java crash or ANR. `CrashReports.lastSessionCrashed()`
  decides this from the newest saved report, because the launcher's `onResume` collects reports
  concurrently.

Any touch or key during those 1.5 s keeps the launcher open, for example to change the driver.
Development scripts can still pass `--ez play true` to start the game immediately.
