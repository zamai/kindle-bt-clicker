# kindle-bt-clicker

Goal: turn pages on a jailbroken Kindle Paperwhite 5 (11th gen, FW 5.19.2, MT8110 "Bellatrix")
with a Bluetooth clicker. This repo currently holds the **dev feedback loop**: drive the Kindle
from the Mac and see its screen.

## Feedback loop (works)

| Thing | How |
|---|---|
| Shell | root SSH over Wi-Fi, port 2222, KOReader's patched dropbear, key `~/.ssh/kindle_ed25519` |
| See screen | `./kctl shot` → `shots/latest.png` (+ timestamped copy), ~1.3 s, reads `/dev/fb0` (Y8, 1236x1648, stride 1248) |
| Touch | `./kctl tap X Y`, `swipe X1 Y1 X2 Y2 [ms]`, `next`, `prev` — writes MT protocol-B events into `/dev/input/event1` (pt_mt) via KOReader's luajit (`kindle/inject.lua`) |
| Verify | `./kctl check next` → exit 0 if the screen changed |
| Run cmd | `./kctl sh '<cmd>'` |
| Find IP | `./kctl find` (nmap the /24 for :2222, cached in `.kindle_ip`) |

Verified: stock reader turns pages forward/back; home screen taps work.

### Gotcha found
Lab126's X `multitouch.so` treats `ABS_MT_TRACKING_ID` as a finger index — it must be small (real
hardware sends `0`). A large random id is logged by the GestureEngine but never becomes a button press.
Also the input core drops ABS values identical to the slot's last value, so vary pressure/size.
Debug: `grep GestureEngine /var/log/messages` shows `Sending button 1 down/up` for accepted touches.

## One-time setup (already done)
1. Over USB mass storage: `koreader/settings/SSH/authorized_keys` ← our pubkey; KOReader settings
   `SSH_autostart=true`, `SSH_key_only_auth=true` (original backed up in `backup/`).
2. `documents/BTClicker-SSH.sh` scriptlet (source in `kindle/`) — tap it in the library to start
   dropbear on :2222, disable screensaver, show IP on screen.

**Persistent across reboots** (upstart, both start on `framework_ready`):
- `/etc/upstart/btclicker-ssh.conf` (source `kindle/btclicker-ssh.upstart`): waits until `/mnt/us` is really
  mounted (booting with USB plugged in exports it to the Mac when `framework_ready` fires), then starts
  `hid-passthrough` and runs dropbear on :2222. KOReader's own SSH autostart is turned off to avoid a port clash.
- `/etc/upstart/hid-passthrough.conf`: official job, enabled via `curl 127.0.0.1:8321/autostart?enable=1`
  (same as BTManager's "Start on boot"); gives up after 3 unstable starts (`boot_attempts`).
- `/etc/upstart/kindle-button-mapper.conf`: installed by the khp installer.
- If the Mac mounts the Kindle as a drive after boot, eject it (`diskutil eject /Volumes/Kindle`):
  while mounted the Kindle can't see its own storage.
- Fallback if SSH is ever gone: tap "BTClicker SSH" in the library.
- Undo: `mntroot rw; rm /etc/upstart/btclicker-ssh.conf; mntroot ro` and `curl 127.0.0.1:8321/autostart?enable=0`.

## Step 2: Bluetooth -> page turn (works)

```
Mac (CoreAudio volume of "Kindle PW5")  --AVRCP SetAbsoluteVolume-->  Kindle radio /dev/stpbt
  -> kindle-hid-passthrough (Bumble, media-remote mode: A2DP sink + AVRCP target)
  -> "Phone Media Remote" uhid keyboard: vol up = PageDown(109), vol down = PageUp(104)
  -> kindle-button-mapper  -> scripts/kindle.sh next_page|prev_page  -> stock reader turns
```

| Command | What |
|---|---|
| `./kctl bt next\|prev` | send a page turn over Bluetooth (`mac/kturn`, nudges the Kindle device volume, default output untouched) |
| `./kctl btcheck next\|prev` | same + screenshot diff, exit 0 if page changed |
| `./kctl btconnect` | reconnect the Mac to the Kindle (`btmac blueutil --connect`) |

Why not "Mac pretends to be a clicker"? macOS CoreBluetooth refuses to publish the HID service
(`0x1812`: "The specified UUID is not allowed"), and IOBluetooth has no HID-device mode. The
media-remote path is the closest real-radio stand-in and runs through the same daemon, uhid, mapper.

### Setup that was needed
- kindle-hid-passthrough v3.20.0 installed with `scripts/install.sh installAll` (no boot autostart).
  Starts on boot (see above). Manual restart with debug logging: `sh /mnt/us/btclicker/khp-restart.sh [debug|hci]`.
- **Patched Bumble** (`patches/patch_flush_timeout.py`): macOS puts an L2CAP FLUSH_TIMEOUT option in
  the A2DP media-channel config; Bumble 0.0.226 rejects unknown options, macOS retries ~160x and drops
  after 10 s (Android doesn't send it, so upstream never hit this). The patch is a 2-byte edit of the
  bytecode inside `dist/main.bin`; original kept as `dist/main.bin.orig`. A `kpm upgrade`/reinstall
  overwrites it - rerun the patch. Worth reporting upstream.
- Button mapper: `[device.media_remote]` block appended to `/mnt/us/kindle-button-mapper/config.ini`
  (copy in `kindle/button-mapper-media-remote.ini`, original backed up as `config.ini.orig`).
- Mac: `brew install blueutil switchaudio-osx`; Bluetooth TCC for tools started from Claude is denied,
  so they run via `mac/BTRun.app` (`./btmac <cmd>`), allowed once in Privacy & Security > Bluetooth.
  Pairing: `curl 127.0.0.1:8321/discoverable?duration=300` on the Kindle, then `btmac blueutil --pair`.

### Gotchas
- Opening **BT Manager** on the Kindle auto-scans, which suspends the daemon and drops the Mac link.
- `pgrep -f`/`pkill -f` over ssh match the ssh command line itself; use `[d]ist/main[.]bin` style patterns.

## Step 3: Real clicker (works)

"Bluetooth remote RL7" (BLE, AA:BB:CC:DD:EE:FF), paired over SSH through the daemon API
(`/scan`, `/scan-status`, `/pair?addr=...&protocol=ble`, `/pair-status` on 127.0.0.1:8321),
so the BT Manager UI isn't needed. It shows up as /dev/input/eventN, named "Bluetooth remote RL7".

**Controls:** click = next page; hold 500 ms or longer = previous page. The previous-page
turn fires while the button is still held.

- Both buttons send the same key: KEY_VOLUMEUP (115, consumer usage 0xC00E9). The HID
  descriptor is only 27 bytes, so the Kindle can't tell the buttons apart.
- Its uhid input device has no EV_REP (EV=13), so no autorepeat. kindle-button-mapper's
  `[device.X.longpress]` waits for repeat events and never fires; a held press comes out as a click.
- The fix is my own handler, `kindle/longpress.lua`. It grabs the device, times the press with
  poll(), and rescans for the device after a disconnect. It runs from the boot job
  `kindle/rl7-clicker.upstart` (installed as /etc/upstart/rl7-clicker.conf) and logs to
  /var/log/rl7-clicker.log. The RL7 block that pairing auto-adds is removed from the mapper's
  config.ini so the mapper doesn't grab the device.
- **Power:** a press while the screen saver is up only wakes the Kindle (`lipc-set-prop com.lab126.powerd powerButton 1`)
  and turns no page; presses in the next 3 s are ignored while it wakes. Every page turn resets the
  screen-saver timer (`lipc-set-prop -i com.lab126.powerd touchScreenSaverTimeout 1`), so reading
  with the remote keeps the Kindle awake like touching the screen does.
- To see what a device sends: `kindle/evlog.lua DEV SECONDS` (KOReader's luajit; stop
  whatever grabs the device first).
- Undo: `mntroot rw; rm /etc/upstart/rl7-clicker.conf; mntroot ro; stop rl7-clicker`.
- Verified 2026-11-15 in the stock reader: a click turned forward and a hold turned back. Also verified after a reboot: the remote reconnected with no click (25 s after boot), and again after the Kindle had been asleep.

## Next steps (from research)
- Install `usbnetlite` (KPM) as a USB-SSH fallback before touching the BT stack.
- Buy/pair a real clicker (AB Shutter 3 / 8BitDo Micro): `kindle-hid-passthrough --pair`, map its keycodes in the mapper.
- KOReader ≥ 2026.07 (have v2026.07.1) + its plugin is the easy path; stock reader needs
  kindle-button-mapper-rs → fake taps (exactly what `inject.lua` does).
