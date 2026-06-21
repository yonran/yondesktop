# Battery longevity & swelling avoidance (yonnas, `MacBookPro14,1`)

This server is a 2017 13" MacBook Pro (`MacBookPro14,1`, two Thunderbolt ports, legacy
SMC, no T1/T2) running NixOS 24/7 on AC power. Its internal Li-ion pack is therefore
**held at 100% charge and kept warm continuously** — the single worst condition for
Li-ion aging and the leading cause of swelling ("spicy pillow"), which on an unattended
box is a real fire/expansion hazard.

This doc records what was investigated, why a clean software charge limit is **not**
available on this hardware, and the mitigations we apply.

## Current state (snapshot 2026-06-20)

Battery is healthy now — there is a comfortable window to act before degradation starts:

| Metric | Value | Source |
| --- | --- | --- |
| `status` | `Full` (pinned at 100%) | `/sys/class/power_supply/BAT0/status` |
| `capacity` | 101% | ACPI battery |
| `cycle_count` | 49 | ACPI battery |
| `charge_full` / `charge_full_design` | 4961 / 4850 mAh (~102%) | ACPI battery |
| `temp` | ~30 °C | ACPI battery |
| manufacturer / model | DSY / `bq20z451` | ACPI battery |

## Why there is no *native* Linux charge limit (and how we added one)

Mainline Linux exposes no charge cap on this Mac; we added one out-of-tree
(`applesmc-bclm`, below). Two different drivers are involved upstream, and neither
bridges read-out to control:

- **Battery *read-out* comes from ACPI**, not applesmc: `BAT0` lives at
  `…/PNP0C09:00/ACPI0001:00/ACPI0002:00/power_supply/BAT0` (HID `ACPI0002` = **Smart
  Battery (SBS)**, owned by `sbs.ko`/`sbshc.ko` — *not* the control-method
  `battery.ko`). There is **no** `charge_control_*_threshold` file — Apple's firmware
  exposes no ACPI charge-limit method. (Note: `sbs.c` has no battery-hook API, so the
  charge-limit knob below attaches by looking the battery up with
  `power_supply_get_by_name` instead of via a hook.)
- **The charge *lever* is an SMC key**, owned by `applesmc` — but `applesmc` is an
  **hwmon** driver (fans/temps/accelerometer/light). It does not implement the
  `power_supply` charge-control properties. Its generic SMC-key sysfs interface
  (`key_at_index*`) is **read-only by index**; there is no node to *write* a key.
- A generic SMC-key-write interface was proposed on linux-hwmon in Nov 2020 and
  **rejected** by the maintainer; nothing has landed for Intel `applesmc` since (the
  last functional change to the driver was 2020). Confirmed on kernel 6.18.35.
- The mature in-kernel charge work is the Asahi **`macsmc`** driver for **Apple
  Silicon** (M-series) — a different SMC/driver entirely, and even there the charge
  threshold properties were dropped from the merged power driver. **Not applicable.**

### The SMC charge lever does exist on this box (read-only)

The discovery method is: enumerate all SMC keys, then identify the one whose value
changes when charging behavior changes (the "diff" method that pinned down `BCLM`).
You can enumerate keys live via applesmc:

```sh
sudo bash -c '
d=/sys/devices/platform/applesmc.768
n=$(cat $d/key_count)              # 798 keys on this machine
for ((i=0;i<n;i++)); do
  echo $i > $d/key_at_index
  name=$(cat $d/key_at_index_name)
  case "$name" in B*|CH*|AC*)
    printf "%s\t%s\t%s\n" "$name" "$(cat $d/key_at_index_type)" \
      "$(od -An -tu1 $d/key_at_index_data)" ;;
  esac
done'
```

Relevant keys found (2026-06-20):

| Key | Type | Value | Meaning |
| --- | --- | --- | --- |
| `BCLM` | `ui8` | `100` | **Battery Charge Limit Max (%)** — the macOS bclm/AlDente lever. Set 80 ⇒ cap at 80%. |
| `CH0B` | `hex_` | `0` | Charger behavior/inhibit (0 = charging allowed). |
| `BWLM` | `ui8` | `0` | Low/warn limit. |
| `ACLM` | `ui16` | — | AC current limit. |
| `B0FC` / `B0DC` | `ui16` | 4966 / 4850 | SMC full / design capacity — cross-checks the ACPI `charge_full`/`_design`. |

So the lever physically exists. Mainline `applesmc` can only *read* `BCLM`; writing it
needs a patched driver.

### Our write path: `applesmc-bclm` (built, tested, in use)

`./applesmc-bclm/` is a minimal out-of-tree patch to `applesmc` that adds the standard
`power_supply` `charge_control_end_threshold` attribute (backed by `BCLM`) on
`/sys/class/power_supply/BAT0/` — attached by looking the battery up with
`power_supply_get_by_name` (no `sbs`/`battery` hook). Tested on this box: writing `80`
sets the SMC `BCLM` key to `80` (confirmed via the independent `key_at_index` dump);
end-to-end, on AC the battery charged and **stopped at the cap** (`status=Full`,
`current_now=0`, gauge `capacity=79%`) instead of reaching 100%; and **`BCLM` persists
in the SMC** after unloading the patched module and restoring the stock driver. So the
cap is currently set to **80%** and active under the stock driver. See
`./applesmc-bclm/README.md` for the set/change procedure and persistence options.

### Out-of-tree alternative we did NOT use: `applesmc-next`

`applesmc-next` (DKMS, <https://github.com/c---/applesmc-next>) also writes `BCLM`, but
we rejected it because, as shipped, it:

1. Ships a **forked `sbs`/`sbshc`** to add a battery hook (our `BAT0` is an SBS battery
   and mainline `sbs.c` has no hook API), and that forked `sbshc` is exactly what
   **kernel-oopses** on several non-T2 Intel Macs / 7.x kernels (issues #14/#15) —
   unacceptable on an unattended server. `applesmc-bclm` sidesteps this entirely by
   looking the battery up by name, touching neither `sbs` nor `battery`.
2. Has **no tested report on `MacBookPro14,1`**.

## Mitigation plan

Ordered best-first.

1. **Charge limit via `applesmc-bclm` (implemented; primary).** Cap set to **80%**
   (`BCLM`), persists in the SMC under the stock driver. This directly fixes the
   held-at-100% aging without removing the battery. See `./applesmc-bclm/README.md` for
   how it was built/tested and the persistence options (it's set in the SMC now; wiring
   a boot-time re-assert into NixOS is the remaining follow-up).

2. **Thermal — keep the pack cool (implemented).** Heat drives both capacity fade and
   swelling, and the cells sit right under the logic board.
   - `services.mbpfan.enable = true` (in `configuration.nix`). The fan was idle (0 rpm)
     under SMC's conservative auto curve; mbpfan runs it proactively (aggressive default:
     ramp from 58 °C, full at 78 °C, auto 1200–7200 rpm) to cool the area around the cells.
   - *Optional* CPU heat cap (commented in `configuration.nix`): limit `intel_pstate`
     `max_perf_pct` to ~80 to cut peak temps. Jellyfin transcodes via VAAPI so real
     workload is barely affected; trade-off is slightly slower CPU-bound bursts.

3. **Monitoring / early warning (implemented).** node_exporter already exports
   `node_power_supply_*` for `BAT0`. Alert rules added in `home-monitoring.nix`:
   - `BatteryOverheatWarn` ≥ 40 °C / `BatteryOverheatCrit` ≥ 45 °C (sustained heat =
     swelling precursor).
   - `BatteryHealthLow`: `charge_full / charge_full_design < 0.8` (degrading pack —
     inspect for swelling, consider replacement/disconnect).
   These expressions return empty (don't fire) if the battery is later disconnected.

### Fallback options (not needed now that the charge limit works)

- **Physically disconnect / remove the pack (definitive).** Eliminates the swelling/fire
  risk entirely. ⚠️ 2016–2017 Intel MBPs **throttle the CPU hard** with no battery
  present (SMC limits current draw from the charger alone), so test workload tolerance.
- **Smart-plug + Home Assistant charge band.** Charger on a smart plug; HA reads `BAT0`
  `capacity` (via the existing MQTT broker) and toggles the charger to cycle 60–80%.
  Superseded by `applesmc-bclm`, which needs no extra hardware.

## References

- Mainline applesmc (no charge control): <https://github.com/torvalds/linux/blob/master/drivers/hwmon/applesmc.c>
- 2020 SMC-key-write proposal (rejected): <https://www.spinics.net/lists/linux-hwmon/msg09839.html>
- `applesmc-next` + issues #16/#15/#14/#8: <https://github.com/c---/applesmc-next>
- Apple Silicon `macsmc-power` (Intel-irrelevant; thresholds dropped): <https://lwn.net/Articles/1059189/>
