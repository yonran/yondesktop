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

## Why there is no native Linux charge limit on this Mac

Two different drivers are involved, and neither bridges read-out to control:

- **Battery *read-out* comes from ACPI**, not applesmc: `BAT0` lives at
  `…/PNP0C09:00/ACPI0001:00/ACPI0002:00/power_supply/BAT0` (HID `ACPI0002`, ACPI
  Control-Method Battery, `drivers/acpi/battery.c`). There is **no**
  `charge_control_start_threshold` / `charge_control_end_threshold` file — Apple's
  firmware exposes no ACPI charge-limit method.
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

So the lever physically exists and currently reads "no limit." The only gap is that
mainline `applesmc` lets us *read* `BCLM` but not *write* it.

### Out-of-tree write path (NOT used — too risky for a 24/7 box)

`applesmc-next` (DKMS, <https://github.com/c---/applesmc-next>) patches applesmc to write
`BCLM` and create `charge_control_end_threshold`. We rejected it because, as shipped, it:

1. Hooks `sbs_hook_register()` (SMBus Smart Battery), but our `BAT0` is an ACPI
   Control-Method battery on `drivers/acpi/battery.c` — a different hook list, so the
   sysfs file never appears without the unmerged issue #16 patch.
2. Bundles a forked `sbs`/`sbshc` that kernel-**oopses** on several non-T2 Intel Macs
   and on 7.x kernels (issues #14/#15) — unacceptable on an unattended server.
3. Has **no tested report on `MacBookPro14,1`**.

## Mitigation plan

Ordered best-first. The first two are out-of-repo (hardware/HA) decisions; the rest are
implemented in this repo.

1. **Physically disconnect / remove the pack (definitive).** For a 24/7 AC server the
   battery is pure liability. Disconnecting the battery connector eliminates the
   held-at-100%-hot aging and the swelling/fire risk entirely.
   - ⚠️ Caveat: 2016–2017 Intel MBPs are known to **throttle the CPU hard** with no
     battery present (the SMC limits current draw from the charger alone). Test whether
     the NAS workload tolerates it before committing.

2. **Smart-plug + Home Assistant charge band (best software-only).** Put the charger on
   a smart plug; HA reads `BAT0` `capacity` (publish over the existing MQTT broker) and
   switches the charger **off at ~80%, on at ~60%**. The pack then cycles gently in the
   ideal 60–80% band, never sits at 100%, and stays connected (no CPU throttle). Needs
   one smart plug.

3. **Thermal — keep the pack cool (implemented).** Heat drives both capacity fade and
   swelling, and the cells sit right under the logic board.
   - `services.mbpfan.enable = true` (in `configuration.nix`). The fan was idle (0 rpm)
     under SMC's conservative auto curve; mbpfan runs it proactively (aggressive default:
     ramp from 58 °C, full at 78 °C, auto 1200–7200 rpm) to cool the area around the cells.
   - *Optional* CPU heat cap (commented in `configuration.nix`): limit `intel_pstate`
     `max_perf_pct` to ~80 to cut peak temps. Jellyfin transcodes via VAAPI so real
     workload is barely affected; trade-off is slightly slower CPU-bound bursts.

4. **Monitoring / early warning (implemented).** node_exporter already exports
   `node_power_supply_*` for `BAT0`. Alert rules added in `home-monitoring.nix`:
   - `BatteryOverheatWarn` ≥ 40 °C / `BatteryOverheatCrit` ≥ 45 °C (sustained heat =
     swelling precursor).
   - `BatteryHealthLow`: `charge_full / charge_full_design < 0.8` (degrading pack —
     inspect for swelling, consider replacement/disconnect).
   These expressions return empty (don't fire) if the battery is later disconnected.

## References

- Mainline applesmc (no charge control): <https://github.com/torvalds/linux/blob/master/drivers/hwmon/applesmc.c>
- 2020 SMC-key-write proposal (rejected): <https://www.spinics.net/lists/linux-hwmon/msg09839.html>
- `applesmc-next` + issues #16/#15/#14/#8: <https://github.com/c---/applesmc-next>
- Apple Silicon `macsmc-power` (Intel-irrelevant; thresholds dropped): <https://lwn.net/Articles/1059189/>
