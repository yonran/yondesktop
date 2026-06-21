# applesmc-bclm — battery charge limit for the Intel MacBook Pro NAS

Patched `applesmc` that exposes a writable charge-limit knob backed by the SMC
`BCLM` key ("Battery Charge Level Max"). This is the software charge cap that
mainline Linux does not provide on Intel Macs (see `../battery.md` for why).

```sh
cat   /sys/devices/platform/applesmc.768/charge_control_end_threshold   # current cap (100 = no limit)
echo 80 > /sys/devices/platform/applesmc.768/charge_control_end_threshold   # cap charging at 80%
```

**Status: tested working on this NAS (`MacBookPro14,1`, kernel 6.18.35).** Writing 80
set the SMC `BCLM` key to 80 (verified independently via the `key_at_index` dump),
charging stopped (`current_now=0`), and **the value persists in the SMC** — it still
read 80 after unloading the patched module and restoring the stock driver. So the cap
stays in effect without the patched module needing to remain loaded.

## What the patch does

`bclm.patch` (applied to the stock v6.18 `drivers/hwmon/applesmc.c`, vendored here as
`applesmc.c`):

- Adds a `charge_control_end_threshold` show/store that reads/writes the `BCLM` ui8
  key (validated to 10–100).
- Creates that attribute **on applesmc's own platform device**
  (`/sys/devices/platform/applesmc.768/`), guarded by `applesmc_has_key("BCLM")` so
  it's a no-op on Macs without the key.

### Why the platform device and not `/sys/class/power_supply/BAT0/`

On this Mac, `BAT0` is a **Smart Battery (ACPI `ACPI0002`, owned by `sbs.ko`)**, not a
control-method battery (`PNP0C0A`/`battery.ko`). Mainline `sbs.c` has **no** battery-hook
API to attach a sysfs attribute to (only the control-method `battery.c` exports
`battery_hook_register`). The first attempt used `battery_hook_register` and failed to
load (`Unknown symbol`, because `battery.ko` isn't even used here). `applesmc-next`
works around this by shipping a *forked* `sbs`/`sbshc` — which is exactly the part that
oopses on several Intel Macs, so we avoid it. Writing `BCLM` is a pure SMC operation
independent of how the battery is read, so hanging the knob off applesmc's platform
device works regardless and adds no module dependencies.

The vendored `applesmc.c` is stock `v6.18` (pristine sha256 `2fc482268abf12…`) plus
`bclm.patch`. On a kernel upgrade where upstream applesmc changes, re-fetch the new
`applesmc.c` and re-apply `bclm.patch` (the build fails loudly if the patch is stale).

## Build (safe — does not load anything)

On the box, against the running kernel (downloads the cached kernel `dev` output; no
kernel recompile):

```sh
nix-build --no-out-link -E 'let s = import <nixpkgs/nixos> {}; \
  in s.config.boot.kernelPackages.callPackage ./default.nix {}'
# -> .../lib/modules/6.18.35/misc/applesmc.ko   (vermagic matches; no extra symbol deps)
```

## Set / change the cap (reversible)

Because `BCLM` persists in the SMC, you only need the patched module loaded long enough
to write the value:

```sh
KO=$(nix-build --no-out-link -E 'let s=import <nixpkgs/nixos> {}; in s.config.boot.kernelPackages.callPackage ./default.nix {}')/lib/modules/6.18.35/misc/applesmc.ko
sudo rmmod applesmc && sudo insmod "$KO"          # swap in the patched driver
echo 80 | sudo tee /sys/devices/platform/applesmc.768/charge_control_end_threshold
sudo rmmod applesmc && sudo modprobe applesmc     # back to the stock driver; BCLM stays 80
```

To remove the cap, set it back to `100` the same way.

⚠️ `rmmod`/`insmod` of `applesmc` on the remote NAS carries a small hang risk that could
need physical access; a reboot restores the stock module. (mbpfan, if enabled, uses
applesmc's fan sysfs — stop it first: `systemctl stop mbpfan`.)

## Persistence

`BCLM` is retained by the SMC across driver reload, and SMC keys of this type are
expected to survive reboots too (not yet verified across a full reboot on this box —
a reboot here locks the ZFS pools until web-unlock). Options:

1. **Leave it set (simplest).** It's set to 80 now and persists. Re-run the swap above
   only if the SMC ever resets (battery disconnect, SMC reset, firmware update).
2. **Re-assert on boot.** Add a boot-time mechanism that ensures `BCLM` is at the target.
   Stock applesmc can't write it, so this needs the patched module — either:
   - `boot.extraModulePackages = [ (config.boot.kernelPackages.callPackage ./. {}) ]`
     to make this the system `applesmc`, then a `systemd.tmpfiles`/oneshot writing the
     knob on boot. Caveat: verify modprobe prefers the `misc/` copy over the in-tree
     `applesmc.ko` (module-name shadowing); validate after a reboot.
   - `boot.kernelPatches = [ { name = "applesmc-bclm"; patch = ./bclm.patch; } ]`
     — cleanest (no shadowing) but rebuilds the whole kernel (slow on this 2-core box).
