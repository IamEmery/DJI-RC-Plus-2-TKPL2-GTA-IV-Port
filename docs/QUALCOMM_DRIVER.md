# Research: the proprietary Adreno driver on the RC Plus 2

**Result: it works, but it is not faster than Turnip.** Kept here as notes;
the shipped configuration uses the bundled Mesa Turnip driver.

## Why it does not work out of the box

The renderer needs Vulkan 1.2 with `dynamicRendering` and `shaderInt64`.

| Driver | Vulkan on the Adreno 643 |
|---|---|
| System driver (`vulkan.adreno.so`, compiler EV031.35.01.12) | 1.1.128, no dynamic rendering |
| AdrenoTools packages v615.77, v762.10, v805 | 1.1 as well |
| Mesa Turnip 26.3.0-R6 (bundled with the port) | 1.3 |

Spoofing the Android version the driver reads (`ro.build.version.sdk`) changes
nothing.

## What actually caps the version

In the v805 package (`vulkan.ad0805.so`) the API level is the highest bit of a
per-GPU capability mask (`clz` on a mask, stored at `+0x2790` of the device
context; levels 0-4 = Vulkan 1.0-1.4). For the Adreno 643 that mask stops at
1.1. Replacing the `csel` at file offset `0x405c44` of that exact build with
`mov w9, #3` (`52800069`) makes it report Vulkan 1.3.295 with
`dynamicRendering`.

The driver also hides `shaderInt64` on this GPU although its compiler handles
64-bit integers: a test compute shader with 64-bit multiplies gave 256/256
correct results once the feature bit was set. Patch
[0006](../liberty-recomp/patches/0006-vulkan-proxy-qualcomm-shaderint64.patch)
sets that bit in the driver's own feature table from the Vulkan proxy, only
for driver version `0x80325000` and only when the table at the known offset is
byte-identical to what the driver reports.

## Outcome

With both changes the game runs and renders correctly on the Qualcomm driver:
20.2 fps against 21.1 fps on Turnip at the same spot - no gain. The GPU, not
the driver, is the limit (see [PERFORMANCE.md](PERFORMANCE.md)).

No driver binaries are distributed here. The patch applies only to a driver
package you obtain yourself; use it at your own risk.

## Probes

A minimal Vulkan HAL probe (load `HMI`, open `vk0`, create an instance, print
API version, extensions and features) and an int64 compute test made each
check take seconds instead of a game restart. Run them from
`/data/local/tmp` with `LD_LIBRARY_PATH=<driver dir>:/vendor/lib64`.
