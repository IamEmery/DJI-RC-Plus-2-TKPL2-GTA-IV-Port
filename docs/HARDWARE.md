# The controller

| | |
|---|---|
| Device | DJI RC Plus 2 Enterprise (`rc701`, board `lahaina`) |
| SoC | Qualcomm QCS5430: 4 x 1.96 GHz, 3 x 2.4 GHz, 1 x 2.7 GHz, governor `performance` |
| GPU | Adreno 643, 812 MHz max |
| OS | Android 11, kernel 5.4 (QGKI), locked bootloader, OEM unlock not allowed |
| Display | 1920 x 1200, 60 Hz |

## ADB

- USB-C: works out of the box once USB debugging is authorized.
- Wi-Fi: the RC listens for ADB on TCP 5555 and announces itself over mDNS:

  ```
  adb mdns services          # shows adb-<serial>  _adb._tcp  <ip>:5555
  adb connect <ip>:5555
  ```

  Screenshots take ~1.7 s over Wi-Fi; copying is ~6-9 MB/s.

## Notes

- Files you push to `Android/data/<pkg>/` fail with `fchown` errors on Android
  11; push to `/sdcard/Download` and move them. Folders an app creates there are
  private to it, even for `adb shell run-as`.
- **Security:** ADB on port 5555 is reachable from the whole local network.
  Only hosts you authorized can connect, but keep the RC off untrusted
  networks.
- DJI Pilot and the DJI services keep running; with no aircraft attached they
  cost about 6% of one core.
- Overclocking is not possible: the bootloader is locked and the CPU already
  runs at its maximum frequency.
