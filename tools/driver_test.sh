#!/bin/bash
# Turnip driver A/B on the TKPL2: one variant per game launch, since the driver
# reads TU_DEBUG only when it loads.
#   driver_test.sh set <TU_DEBUG value|default>   write env.txt and restart the game
#   driver_test.sh measure <label> [seconds]      sample FPS and GPU busy
set -uo pipefail
# Set ADB_SERIAL when more than one device is attached (e.g. host:5555 over Wi-Fi).
FILES=/sdcard/Android/data/com.libertyrecomp/files
LAYER='SurfaceView - com.libertyrecomp/com.libertyrecomp.LibertyActivity#0'
adbs() { if [ -n "${ADB_SERIAL:-}" ]; then adb -s "$ADB_SERIAL" "$@"; else adb "$@"; fi; }

case "$1" in
set)
  # "default" leaves TU_DEBUG empty, so Turnip picks GMEM or SYSMEM per pass.
  value="$2"; [ "$value" = default ] && value=""
  printf 'TU_DEBUG=%s\n' "$value" | adbs shell "cat > $FILES/.env.tmp && chmod 666 $FILES/.env.tmp && mv $FILES/.env.tmp $FILES/env.txt"
  adbs shell "am force-stop com.libertyrecomp; sleep 1; am start -n com.libertyrecomp/.LauncherActivity --ez play true" >/dev/null
  sleep 6
  adbs shell "cat $FILES/env.txt"
  ;;
measure)
  label="$2"; secs="${3:-10}"; tmp="$(mktemp)"
  adbs shell "dumpsys SurfaceFlinger --latency-clear '$LAYER'" >/dev/null
  gpu=$(adbs shell "s=0; for i in \$(seq $secs); do sleep 1; s=\$((s + \$(cat /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage | tr -dc 0-9))); done; echo \$((s / $secs))")
  adbs shell "dumpsys SurfaceFlinger --latency '$LAYER'" | tr -d '\r' > "$tmp"
  python3 -I - "$tmp" "$label" "$gpu" <<'EOF'
import sys
t = sorted({int(s[1]) for s in (l.split() for l in open(sys.argv[1])) if len(s) == 3 and 0 < int(s[1]) < 2**62})
if len(t) < 3:
    print(sys.argv[2], "no frames"); sys.exit()
d = sorted((b - a) / 1e6 for a, b in zip(t, t[1:]))
print(f"{sys.argv[2]:<22} fps {(len(t)-1)/((t[-1]-t[0])/1e9):5.1f}  median {d[len(d)//2]:5.1f} ms"
      f"  p95 {d[int(len(d)*.95)]:5.1f} ms  gpu {sys.argv[3]:>3}%")
EOF
  rm -f "$tmp"
  ;;
esac
