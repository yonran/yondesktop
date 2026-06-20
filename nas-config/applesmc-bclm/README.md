# applesmc-bclm — battery charge limit for the Intel MacBook Pro NAS

Patched `applesmc` that exposes the standard power_supply charge-limit knob backed
by the SMC `BCLM` key ("Battery Charge Level Max"). This is the software charge cap
that mainline Linux does not provide on Intel Macs (see `../battery.md` for why).

```sh
cat   /sys/class/power_supply/BAT0/charge_control_end_threshold   # current cap (100 = no limit)
echo 80 > /sys/class/power_supply/BAT0/charge_control_end_threshold   # cap charging at 80%
```

## What the patch does

`bclm.patch` (applied to the stock 6.18 `drivers/hwmon/applesmc.c`, vendored here as
`applesmc.c`):

- Adds `charge_control_end_threshold` show/store reading/writing the `BCLM` ui8 key
  (validated to 10–100).
- Attaches it to the battery via the **ACPI battery hook** (`battery_hook_register`),
  which replays for batteries already registered before the module loads — so it works
  regardless of load order. This is the correct hook for our `ACPI0002` control-method
  battery, and avoids the forked-`sbs`/`sbshc` driver that makes `applesmc-next` crash
  on several Intel Macs.
- No-op on Macs without the `BCLM` key (`applesmc_has_key` guard), so it's safe on any
  applesmc machine.

The vendored `applesmc.c` is stock `v6.18` (sha256 `2fc482268abf12...`) plus
`bclm.patch`. On a kernel upgrade where upstream applesmc changes, re-fetch the new
`applesmc.c` and re-apply `bclm.patch` (the build will fail loudly if it's stale).

## Build (safe — does not load anything)

On the box, against the running kernel (downloads the cached kernel `dev` output; no
kernel recompile):

```sh
nix-build -E 'let s = import <nixpkgs/nixos> {}; \
  in s.config.boot.kernelPackages.callPackage ./default.nix {}'
# -> ./result/lib/modules/6.18.35/misc/applesmc.ko
```

## Test (reversible; a reboot restores the stock module)

⚠️ Loading a custom module on the remote NAS carries a small hang risk that could need
physical access. Recovery: the stock `applesmc` returns on the next boot, since nothing
below is persisted.

```sh
sudo systemctl stop mbpfan          # mbpfan uses applesmc's fan sysfs; stop it first
sudo rmmod applesmc                 # drop the stock driver
sudo insmod ./result/lib/modules/6.18.35/misc/applesmc.ko
cat /sys/class/power_supply/BAT0/charge_control_end_threshold   # expect 100
echo 80 | sudo tee /sys/class/power_supply/BAT0/charge_control_end_threshold
# verify status flips to "Not charging" once SoC is >= 80%, and BCLM reads 80
# restore stock:
sudo rmmod applesmc && sudo modprobe applesmc && sudo systemctl start mbpfan
```

## Persistence options (decide after the test)

The `BCLM` value is stored in the SMC and is expected to **persist across reboots**, so
the patched module does not necessarily need to stay loaded — confirm this on the box
during testing. Options, simplest first:

1. **One-shot write, stock driver otherwise.** If BCLM persists, set it once (load the
   patched module, write 80, done). A boot-time oneshot can re-assert it for safety.
2. **`boot.extraModulePackages`.** Ship this module so it loads as `applesmc`. Caveat:
   it would shadow the in-tree `applesmc.ko`; needs verification that depmod/modprobe
   prefer the `misc/` copy (or blacklist + explicit load). Then set the cap via
   `systemd.tmpfiles` / a oneshot writing the sysfs file.
3. **`boot.kernelPatches`.** Cleanest (no module shadowing) but rebuilds the whole
   kernel — slow on this 2-core machine; only worth it if option 2 proves fiddly.
