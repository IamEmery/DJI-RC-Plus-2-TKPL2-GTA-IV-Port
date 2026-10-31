# GTA IV controls on the RC Plus 2

The bridge (`DjiRcJoystickHandler`, patch
[0001](../liberty-recomp/patches/0001-dji-rc-plus2-controls.patch)) turns the
RC into an SDL gamepad laid out like an Xbox 360 controller.

| RC control | Xbox 360 pad |
|---|---|
| Left stick | left stick |
| Right stick | right stick |
| Left rear wheel (either direction) | LT |
| Right rear wheel (either direction) | RT |
| C2 | A |
| C1 | X |
| C3 | RB |
| R1 (F4) | Y |
| L1 (F1) | LB |
| R2 (F5) | B |
| Shutter, half press | LT (aim) |
| Shutter, full press | LT + RT (aim and fire) |
| 5D up / down / left / right | D-pad |
| 5D press | L3 |
| L2 (F2) | R3 |
| Top-right wheel | D-pad left / right (one tap per detent burst) |
| Pause | Start |
| RTH | Back |
| L3, R3, Record, red button, mode switch | free |

The game's own Xbox 360 control scheme applies on top of this.

The wheels act as triggers: the trigger value is the wheel's distance from
its centre, so turning either way presses it. The shutter works like a camera
shutter: a half press aims, pressing on through to the full press fires. When
both the shutter and a wheel drive a trigger, the trigger is fully pressed.

Unarmed, GTA IV punches with B (R2), not with RT.

## Input rate

The DUML report arrives about 10 times per second, so the game sees the sticks
at 10 Hz. The controller also has a USB gamepad ("DJI Virtual Joystick",
`2ca3:1501`, Xbox One protocol, `xpad` driver, 2 ms interrupt endpoint). Its
kernel device (`/dev/input/event4`, readable with `adb shell getevent`)
reports both sticks (`ABS_X/Y`, `ABS_RX/RY`, ±32767) and both back wheels
(`ABS_Z/RZ`, 0-255, centre 127) at about 63 Hz while they move, in games as
well as on the home screen.

Android does not pass those events on: the input dispatcher shows no motion
events from the device, neither in the game window nor at the activity level,
and turning off DJI's "motion via joystick" settings
(`settings global dji_motion_via_{left,right}_joystick_enabled`) does not
change that. The bridge already contains the fast path
(`DjiRcJoystickHandler.onGenericMotion`, wired from
`LibertyActivity.dispatchGenericMotionEvent`): if those events ever reach the
app, the sticks and wheels follow the USB gamepad and DUML stays the fallback.
Each fast axis is compared with DUML on every DUML report, and an axis that
disagrees for about 0.4 s goes back to DUML for 2 s. The logcat status line
counts them as `fast events=N fallbacks=N`. Until then the rate stays at 10 Hz.

## How it works

- `DjiRcJoystickHandler.install()` replaces SDL's joystick handler right after
  `SDLActivity.onCreate`.
- On `detectDevices()` it registers a virtual gamepad (`2ca3:1502`) **before**
  the system's devices, so the game, which reads player 0, gets the RC. The
  "DJI Virtual Joystick" (`2ca3:1501`) is hidden from SDL, otherwise it would
  take player slot 0.
- A daemon thread "DjiRcBridge" keeps the DUML connection, reconnects every
  second and releases every input when the connection drops.
- `LibertyActivity.dispatchKeyEvent` forwards `F1`-`F6` (without repeats).
- Input state has its own lock: SDL calls `detectDevices()` while holding its
  joystick lock, and the bridge thread takes that lock inside `onNativeJoy` /
  `onNativePad*`, so sharing the handler's monitor would deadlock.

The bridge still carries its own copy of the protocol code; the same code is
available as the `djirc` library in the companion repository
[DJI RC Plus 2 (TKPL2) Native Gamepad Bridge for Gaming](https://github.com/iamemery/DJI-RC-Plus-2-TKPL2-Native-Gamepad-Bridge-for-Gaming) for other ports.
