#!/bin/bash
# Live A/B test of renderer features on the TKPL2 (DJI RC Plus 2).
# Stand still with a fixed camera in a busy spot; each variant changes one
# setting through live_cvars.txt, settles, then samples FPS and GPU busy.
#   ab_test.sh [settle_s] [measure_s]
set -uo pipefail
SETTLE="${1:-4}"
MEASURE="${2:-8}"
FILES=/sdcard/Android/data/com.libertyrecomp/files
LAYER='SurfaceView - com.libertyrecomp/com.libertyrecomp.LibertyActivity#0'
TMP="$(mktemp -d)"

# Unlocked frame rate and a fixed draw distance, so FPS shows real headroom.
BASE=(
  --gta4_frame_limit=0
  --gta4_dynamic_draw_distance=false
  --gta4_draw_distance_scale=0.85
  --gta4_native_water_reflection_interval=1
  --gta4_native_shadow_min_indices=150
  --gta4_native_anti_aliasing=fxaa
  --gta4_reflection_capture_distance=near
  --gta4_fps_guard=0
)

# The game re-reads live_cvars.txt when its mtime changes, so the file must
# already be readable when it appears: write and chmod a temp file, then rename.
apply() {
  printf '%s\n' "$@" | adb shell "cat > $FILES/.live.tmp && chmod 666 $FILES/.live.tmp && mv $FILES/.live.tmp $FILES/live_cvars.txt"
}

measure() {
  local label="$1" out="$TMP/lat.txt" gpu=0 n=0
  : > "$out"
  adb shell "dumpsys SurfaceFlinger --latency-clear '$LAYER'" >/dev/null
  for _ in $(seq "$MEASURE"); do
    sleep 1
    adb shell "dumpsys SurfaceFlinger --latency '$LAYER'" | tr -d '\r' >> "$out"
    gpu=$((gpu + $(adb shell cat /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage | tr -dc '0-9')))
    n=$((n + 1))
  done
  python3 -I - "$out" "$label" "$((gpu / n))" <<'EOF'
import sys
p = set()
for l in open(sys.argv[1]):
    s = l.split()
    if len(s) == 3:
        t = int(s[1])
        if 0 < t < 2**62:
            p.add(t)
t = sorted(p)
if len(t) < 3:
    print(f"{sys.argv[2]:<34} no frames"); sys.exit()
span = (t[-1] - t[0]) / 1e9
d = sorted((b - a) / 1e6 for a, b in zip(t, t[1:]))
print(f"{sys.argv[2]:<34} fps {(len(t)-1)/span:5.1f}  median {d[len(d)//2]:5.1f} ms"
      f"  p95 {d[int(len(d)*.95)]:5.1f} ms  gpu {sys.argv[3]:>3}%", flush=True)
EOF
}

variant() {
  local label="$1"; shift
  apply "${BASE[@]}" "$@"
  sleep "$SETTLE"
  measure "$label"
}

echo "settle ${SETTLE}s, measure ${MEASURE}s per variant"
variant "baseline (uncapped)"
variant "water reflection off"        --gta4_native_water_reflection_interval=0
variant "shadows: small draws off"    --gta4_native_shadow_min_indices=100000
variant "draw distance 0.5"           --gta4_draw_distance_scale=0.5
variant "anti-aliasing off"           --gta4_native_anti_aliasing=off
variant "env reflection guard"        --gta4_fps_guard=3
variant "all of the above"            --gta4_native_water_reflection_interval=0 \
  --gta4_native_shadow_min_indices=100000 --gta4_draw_distance_scale=0.5 \
  --gta4_native_anti_aliasing=off --gta4_fps_guard=3
variant "baseline again"

# Back to the normal profile: 30 FPS cap and dynamic draw distance.
apply --gta4_frame_limit=30 --gta4_dynamic_draw_distance=true \
  --gta4_draw_distance_scale=0.85 --gta4_native_water_reflection_interval=1 \
  --gta4_native_shadow_min_indices=150 --gta4_native_anti_aliasing=fxaa --gta4_fps_guard=3
echo "restored the normal profile"
rm -rf "$TMP"
