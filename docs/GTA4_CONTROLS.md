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
| C3 | B |
| R1 (F4) | Y |
| L1 (F1) | LB |
| Shutter, full press | RB |
| 5D up / down / left / right | D-pad |
| 5D press | L3 |
| L2 (F2) | R3 |
| Top-right wheel | D-pad left / right (one tap per detent burst) |
| Pause | Start |
| RTH | Back |
| L3, R2, R3, Record, shutter half press, red button, mode switch | free |

The game's own Xbox 360 control scheme applies on top of this.

The wheels act as triggers: the trigger value is the wheel's distance from
its centre, so turning either way presses it.

## How it works

- `DjiRcJoystickHandler.install()` replaces SDL's joystick handler right after
  `SDLActivity.onCreate`.
- On `detectDevices()` it registers a virtual gamepad (`2ca3:1502`) **before**
  the system's devices, so the game, which reads player 0, gets the RC. The
  silent "DJI Virtual Joystick" (`2ca3:1501`) is hidden, otherwise it would take
  player slot 0.
- A daemon thread "DjiRcBridge" keeps the DUML connection, reconnects every
  second and releases every input when the connection drops.
- `LibertyActivity.dispatchKeyEvent` forwards `F1`-`F6` (without repeats).
- Input state has its own lock: SDL calls `detectDevices()` while holding its
  joystick lock, and the bridge thread takes that lock inside `onNativeJoy` /
  `onNativePad*`, so sharing the handler's monitor would deadlock.

The bridge still carries its own copy of the protocol code; the same code is
available as the `djirc` library in the companion repository
[DJI RC Plus 2 (TKPL2) Native Gamepad Bridge for Gaming](https://github.com/iamemery/DJI-RC-Plus-2-TKPL2-Native-Gamepad-Bridge-for-Gaming) for other ports.
