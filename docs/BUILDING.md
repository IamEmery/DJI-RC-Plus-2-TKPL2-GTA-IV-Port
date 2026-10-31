# Building the patched LibertyRecompAndroid on macOS

Upstream builds Android only on Windows with Git Bash (see upstream `docs/android/BUILDING.md`).
This page describes the build that produced the libraries used here, done directly with CMake and
Gradle on macOS (Intel), without upstream's Git Bash scripts.

> No game files are part of this repository or of upstream. You need your own disc image and
> Title Update 8; install them on the device with the app's installer.

## Prerequisites

| Tool | Version used |
|---|---|
| Android NDK | **r29 `29.0.14206865`** (older NDKs lack `std::jthread`) |
| Android SDK | platform 35, platform-tools |
| JDK | 17 (a standalone JDK, e.g. Temurin; Homebrew source builds are very slow on Intel Macs) |
| CMake | 3.29+ |
| Ninja | 1.11+ |
| Python | 3 |

## 1. Source tree

```sh
git clone --recurse-submodules https://github.com/vaduur/LibertyRecompAndroid.git
cd LibertyRecompAndroid && git checkout v0.5.9.3
python3 tools/setup_repo.py --prepare-only   # pinned dependencies and upstream source patches
git apply /path/to/this-repo/liberty-recomp/patches/*.patch
```

The patches are described in [`liberty-recomp/README.md`](../liberty-recomp/README.md). One patch
edits checked-in generated code (`gta4-recomp/generated/gta4_recomp.77.cpp` and `.78.cpp`). If you
regenerate that code, re-apply the patch.

## 2. Configure

```sh
NDK=$HOME/Library/Android/sdk/ndk/29.0.14206865
cmake -S . -B out/build/android-arm64 -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE=$PWD/toolchains/android.cmake \
  -DANDROID_NDK=$NDK -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-28 \
  -DANDROID_STL=c++_shared -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DLIBERTY_RECOMP_TARGET_PLATFORM=android
```

ThinLTO for `libmain` and the renderer, and the linker symbol-ordering file, are on by default.

## 3. Build

```sh
cmake --build out/build/android-arm64 --target LibertyRecomp -- -j4
```

The first build compiles about 90 large generated files; it takes about 45 minutes at `-j4` on a
6-core Intel Mac. A renderer-only rebuild (`--target rexgpu-gta4-native`) takes about 3 minutes.

## 4. Stage the libraries into the APK

```sh
NB=$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin
J=os/android/app/src/main/jniLibs/arm64-v8a
B=out/build/android-arm64/glue/gta4-recomp
R=glue/rexglue-sdk-main/out/linux-arm64
$NB/llvm-strip --strip-unneeded -o $J/libmain.so          $B/libmain.so
$NB/llvm-strip --strip-unneeded -o $J/libliberty_install.so $B/libliberty_install.so
$NB/llvm-strip --strip-unneeded -o $J/librexruntime.so    $R/librexruntime.so
$NB/llvm-strip --strip-unneeded -o $J/librexgpu-xenos.so  $R/librexgpu-xenos.so
cp $R/librexgpu-gta4-native.so $J/     # keep unstripped: simpleperf can then symbolize the renderer
cp $NDK/toolchains/llvm/prebuilt/darwin-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so $J/
```

`libSDL3.so`, `libvulkan.so` (the Vulkan driver proxy, built by
`os/android/scripts/build_driver_proxy.sh` or its CMake project in `os/android/native`) and the
small hook libraries are built once and kept.

## 5. Package and install

```sh
cd os/android
rm -f app/build/outputs/apk/debug/app-debug.apk
JAVA_HOME=/path/to/jdk17 ANDROID_HOME=$HOME/Library/Android/sdk ./gradlew --no-daemon assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

The APK is debug-signed. If a build signed with a different key (e.g. the official release) is
installed, it must be uninstalled first, which **deletes the installed game and saves**. Back up
your saves first.

## 6. Profile-guided optimization (recommended)

PGO is upstream's pipeline; it covers both `libmain` and the renderer.

```sh
# a) instrumented build
cmake -S . -B out/build/android-arm64 -DLIBERTY_ANDROID_PGO=generate
cmake --build out/build/android-arm64 --target rexgpu-gta4-native LibertyRecomp -- -j4
#    stage (step 4), install (step 5), then play ~10 minutes of typical gameplay
#    (street, driving). The game writes profiles every 60 s:
adb shell run-as com.libertyrecomp ls files/pgo     # libmain-<pid>.profraw, rexgpu-<pid>.profraw
for f in $(adb shell run-as com.libertyrecomp ls files/pgo | tr -d '\r'); do
  adb exec-out run-as com.libertyrecomp cat files/pgo/$f > $f; done

# b) merge and build the optimized libraries
$NB/llvm-profdata merge -o game.profdata *.profraw
cmake -S . -B out/build/android-arm64 -DLIBERTY_ANDROID_PGO=$PWD/game.profdata
cmake --build out/build/android-arm64 --target rexgpu-gta4-native LibertyRecomp -- -j4
#    stage and install again; remove files/pgo on the device
```

The instrumented build runs slower, and its audio stutters while it records; that is expected. After
larger code changes, repeat the cycle; an outdated profile still builds but helps less.

## 7. Runtime configuration

The app reads these files from `Android/data/com.libertyrecomp/files/`:

| File | Purpose | Used here |
|---|---|---|
| `env.txt` | environment for the Vulkan driver | `TU_DEBUG=` (empty: Turnip picks GMEM or sysmem per render pass; the app's default is `sysmem`, which is 15 % slower on the Adreno 643) |
| `args.txt` | game settings (cvars) | upstream `assets/default_args.txt`, unchanged |
| `driver.txt` | driver choice | absent (bundled Turnip 26.3.0-R6) |
| `live_cvars.txt` | settings changed while the game runs | absent in normal use; testing only |

Write files into `Android/data/...` by pushing to `/sdcard/Download` first and moving them with
`adb shell mv`. On this device, `adb push` straight into `Android/data` fails at the end with
`remote fchown failed` and deletes the file.

## 8. Crash analysis without root

The launcher saves a report for every crash, and with these patches it also copies it to the
internal files directory:

```sh
adb shell run-as com.libertyrecomp ls files/crash_reports
adb shell run-as com.libertyrecomp cat files/crash_reports/crash-<date>.txt
adb logcat -b crash                      # the native backtrace
$NB/llvm-objdump -d --start-address=0x<pc-32> --stop-address=0x<pc+8> \
  out/build/android-arm64/glue/gta4-recomp/libmain.so   # unstripped, same BuildId
```
