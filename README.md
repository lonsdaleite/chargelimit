# chargelimit

Keeps the battery of a jailbroken iOS device that lives on a charger between two levels. A small daemon watches
the battery; at the stop level it cuts the current the Lightning port takes from the charger to 0 and holds: the
device runs on battery. At the resume level it restores the port's normal current and charging resumes.

Holding also ends, with charging resumed at once, when the charger is re-plugged, the settings change,
SpringBoard restarts, the device reboots or the daemon restarts. The stop level applies again right after, so the
battery is never charged above it.

Settings → Charge Limit (PreferenceLoader bundle): on/off, stop level 50–100% (100% = no limit) and resume level
10–90%, in 10% steps. The resume list only offers levels below the stop level; lowering the stop level pulls
the resume level down to 10% under it.

## Why the port and not the battery

Battery-side switches (`IsCharging`, `ExternalConnected`, `PredictiveChargingInhibit` on `IOPMPowerSource`, as
used by ChargeLimiter) are accepted and ignored by the charger driver of older iPads. The Lightning port
manager does obey: `IOAccessoryManagerSetUSBCurrentLimitBase` (`libIOAccessoryManager`) on a user client
connection to the `IOAccessoryManager` service limits the input current, measured on a USB meter: 2 A → 0.5 A
with a 500 mA limit, 0 A with 0. `IOAccessoryManagerRestoreUSBCurrentLimitBase` returns the limit the system
negotiated with the charger. The setters take the connection from `IOServiceOpen`, not the service itself;
called on the service they fail with `kIOReturnBadArgument`.

## Devices

- iPad mini 2, iOS 12.5.8, rootful (Amethyst): works.
- iOS 15 (iPad Air 2, Dopamine): does not work, the kernel refuses `IOServiceOpen` on the port manager
  (`kIOReturnNotPermitted`). Not packaged for rootless.
- Other devices and iOS versions are untested.

## Build

```sh
brew install ldid dpkg
make sdk     # downloads the iOS 9.3 SDK into ~/theos/sdks (see scripts/fetch-sdk.sh)
make deb     # build/com.lonsdaleite.chargelimit_<version>_iphoneos-arm.deb
```

Install with `dpkg -i`; the post-install script loads the daemon (`/Library/LaunchDaemons/com.lonsdaleite.chargelimit.plist`,
binary `/usr/libexec/chargelimitd`). Reopen Settings to see the page (`/Library/PreferenceBundles/ChargeLimit.bundle`,
controller `src/ChargeLimitController.m`). The icon is drawn by `scripts/make-icon.py`.

## How the daemon works

- Re-evaluates on any power source change (`com.apple.system.powersources`), on a settings change
  (`com.lonsdaleite.chargelimit.changed`), on `com.apple.springboard.finishedstartup` and every 60 s.
- The holding flag lives only in the daemon's memory. A re-plug is seen as the port limit no longer being 0:
  the system resets it to the charger's limit when the cable is plugged in again.
- Settings are read from the `mobile` user's `com.lonsdaleite.chargelimit` domain: `enabled` (bool), `limit`
  (stop level, percent), `resume` (percent; if not below `limit`, `limit` − 10 is used).
- `make deb EXTRA_CFLAGS=-DCL_DEBUG` builds a daemon that takes the battery level from `/tmp/chargelimit.level`
  when that file exists, to test the levels without waiting for the battery.
- When disabled, set to 100% or stopped with SIGTERM it restores the port limit. `launchctl unload` kills it
  without a signal, so the package's pre-removal script runs `chargelimitd restore` after unloading it.
- State changes go to `/var/mobile/Library/Logs/chargelimit.log`.
