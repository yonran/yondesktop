# Server Crash Log

## 2026-01-21 20:23 PST

**Summary:**

The Thunderbolt-attached USB-C hub (which provides both Ethernet and USB 3.0 for the hard drives) became unresponsive. The `reset-thunderbolt-xhci` service detected the failure and attempted recovery by triggering a PCI rescan of the Thunderbolt hierarchy. The xHCI controller failed to reinitialize (status `0xffffffff` indicates the device was completely unresponsive, error `-19` is `ENODEV`). After the recovery failed, `reset-thunderbolt-xhci` initiated a reboot. However, the reboot hung for 30 minutes because ZFS pools were suspended (disks inaccessible) and couldn't sync. Systemd's `reboot.target` eventually timed out and forced a hard reboot.

**Source:** `journalctl -b -1` (boot prior to current)

**Log lines:**

```
Jan 21 20:23:27 yonnas 6cc70lnankbfivq3gp2fwkxj2lnn3hbl-reset-thunderbolt-xhci[46595]: /nix/store/6cc70lnankbfivq3gp2fwkxj2lnn3hbl-reset-thunderbolt-xhci: line 38: printf: write error: Invalid argument
Jan 21 20:23:34 yonnas 6cc70lnankbfivq3gp2fwkxj2lnn3hbl-reset-thunderbolt-xhci[46595]: PCI rescan triggered for Thunderbolt hierarchy
Jan 21 20:23:34 yonnas kernel: pci 0000:08:00.0: xHCI HW not ready after 5 sec (HC bug?) status = 0xffffffff
Jan 21 20:23:34 yonnas kernel: pci 0000:08:00.0: quirk_usb_early_handoff+0x0/0x7b0 took 5350179 usecs
Jan 21 20:23:34 yonnas kernel: xhci_hcd 0000:08:00.0: xHCI Host Controller
Jan 21 20:23:34 yonnas kernel: xhci_hcd 0000:08:00.0: new USB bus registered, assigned bus number 5
Jan 21 20:23:34 yonnas kernel: xhci_hcd 0000:08:00.0: Host halt failed, -19
Jan 21 20:23:34 yonnas kernel: xhci_hcd 0000:08:00.0: can't setup: -19
Jan 21 20:23:34 yonnas kernel: xhci_hcd 0000:08:00.0: USB bus 5 deregistered
Jan 21 20:23:34 yonnas kernel: xhci_hcd 0000:08:00.0: init 0000:08:00.0 fail, -19
Jan 21 20:23:42 yonnas 6cc70lnankbfivq3gp2fwkxj2lnn3hbl-reset-thunderbolt-xhci[46595]: recovery failed; rebooting to clear wedged Thunderbolt controller
Jan 21 20:23:42 yonnas kernel: zio pool=firstpool vdev=/dev/disk/by-id/wwn-0x5000cca266c21463-part1 error=5 type=2 offset=7748175663104 size=12288 flags=3145856
Jan 21 20:23:42 yonnas kernel: zio pool=firstpool vdev=/dev/disk/by-id/usb-TDAS_TerraMaster_2022091595DA-0:1-part1 error=5 type=2 offset=7748175663104 size=12288 flags=3145856
Jan 21 20:23:42 yonnas kernel: WARNING: Pool 'firstpool' has encountered an uncorrectable I/O failure and has been suspended.
Jan 21 20:23:42 yonnas kernel: zio pool=backuppool vdev=/dev/disk/by-id/wwn-0x5000c500c4cf55a8-part1 error=5 type=1 offset=5821970038784 size=4096 flags=3145856
Jan 21 20:23:42 yonnas kernel: WARNING: Pool 'backuppool' has encountered an uncorrectable I/O failure and has been suspended.
```

**Reboot timeout (ZFS couldn't sync with suspended pools):**

```
Jan 21 20:30:06 yonnas kernel: INFO: task postgres state:D ... blocked for more than 368 seconds.
Jan 21 20:30:06 yonnas kernel: INFO: task zfs:46781 blocked for more than 368 seconds.
Jan 21 20:30:44 yonnas systemd[1]: firstpool.mount: Failed with result 'timeout'.
Jan 21 20:30:44 yonnas systemd[1]: backuppool.mount: Failed with result 'timeout'.
Jan 21 20:53:42 yonnas systemd[1]: reboot.target: Job reboot.target/start timed out.
Jan 21 20:53:42 yonnas systemd[1]: Forcibly rebooting: job timed out
```

**System came back up:** 2026-01-21 20:56:39 PST (per `journalctl --list-boots`)

## 2026-06-04 — Root cause identified: the Realtek RTL8153 USB NIC (`r8152`)

**Summary:**

The recurring whole-system wedge is **triggered by the USB Ethernet adapter, not the disks and not a power brownout.** The Realtek RTL8153 (driver `r8152`, interface `enp7s0u2u4`) hangs its transmit queue; the driver's recovery does a USB device reset, and that reset wedges the *shared* Alpine Ridge xHCI (`0000:07:00.0`) that the TerraMaster DAS also lives on. All USB devices then disconnect, both ZFS pools suspend (`failmode=wait`), and the subsequent reboot hangs ~30 min on the un-syncable pools until `reboot.target`'s built-in 30-min `JobTimeoutAction=reboot-force` fires.

**Hardware context:** MacBookPro14,1 (2017 13", **2 Thunderbolt 3 ports, single JHL6540 controller**). One port = power, one port = a bus-powered `uni` USB-C 4-in-1 hub (Amazon B0871ZL9TG) carrying *both* the r8152 NIC and the D5-300C DAS behind one XHCI. The DAS (TerraMaster D5-300C) is self-powered, USB-C 5 Gbps, internal ASMedia hub.

**Evidence (journald, boots 0..-5):**

- 100% correlation: every crash boot (-1..-5) logged an r8152 distress event; the only healthy boot (0) logged none.

  ```
  boot 0 (alive):  0 r8152 distress events
  boot -1..-5:     1,1,2,1,1   (NETDEV WATCHDOG / Tx timeout / "Stop submitting intr, status -108")
  ```

- Ordering caught directly in boot -3 — the NIC hangs *first*, controller death follows:

  ```
  10:53:23 r8152 enp7s0u2u4: NETDEV WATCHDOG: transmit queue 0 timed out 5184 ms
  10:53:23 r8152 enp7s0u2u4: Tx timeout
  10:53:23 xhci_hcd 0000:07:00.0: xHCI host controller not responding, assume dead
  ```

- Ruled out:
  - **Brownout** — no overcurrent/VBUS/power-budget messages in any crash; DAS is self-powered (light bus load).
  - **PCIe signal integrity** — zero AER/PCIe errors before the hang (silent controller hang).
  - **Scheduled job** — crash uptimes (2h41m, 4h51m, 10h07m, 11h48m, 16h11m) and times-of-day (07:38, 10:53, 16:18, 20:57, 04:40) are random.
  - **The disks** — idle, no precursor I/O errors; they fail only *after* the controller dies.
  - **ASPM idle-sleep** — the NIC is actively passing traffic (constant inbound IPv6 port-scan, ~2400 dropped conns/crash-window) right up to the failure. `power/control` is already forced `on`.

**Mechanism, confirmed in `drivers/net/usb/r8152.c` @ Linux v6.12:**

- `features`/`hw_features` advertise `NETIF_F_TSO | NETIF_F_TSO6 | NETIF_F_SG`, on by default (`r8152.c:9857-9867`). RTL8153 = `RTL_VER_03`+, so TSO is *not* gated off for our chip.
- HW TSO is fragile: transport-offset limit `GTTCPHO_MAX=127` and a 16 KB tx-aggregation buffer force software-segmentation workarounds (`r8152_csum_workaround` `:2210-2249`, `rtl8152_features_check` `:2916-2930`).
- TX watchdog `RTL8152_TX_TIMEOUT = 5*HZ` (`:761`) → `rtl8152_tx_timeout()` → **`usb_queue_reset_device()`** (`:2848-2855`). That USB reset is the line that wedges the shared xHCI.

**Fix applied (this commit):** a udev/device-unit-triggered service disables the implicated TX offloads on `enp7s0u2u4`: `ethtool -K enp7s0u2u4 tso off tx-tcp6-segmentation off gso off` (see `r8152DisableTxOffloadScript` / `systemd.services.r8152-disable-tx-offload` in `configuration.nix`). This is a **source-justified test**, not a certain cure — evidence that offload-disable fixes this is mixed:

- Confirmed root cause via TSO + workaround: <https://groups.google.com/a/chromium.org/g/chromium-os-dev/c/xA2T6WyegQ4>
- But several similar cases were firmware/kernel regressions, not offloads: OpenWrt #22130 <https://github.com/openwrt/openwrt/issues/22130>, Pop!_OS #3600 <https://github.com/pop-os/pop/issues/3600>, Arch BBS #213517 <https://bbs.archlinux.org/viewtopic.php?id=213517>
- One report where offload tuning did NOT help: RPi #5239 <https://github.com/raspberrypi/linux/issues/5239>

**Validation:** need several crash-free days to trust it. If Tx timeouts persist, escalate the offload set (add `sg off` / `tx off`) or, as the permanent fix, move networking off USB entirely onto a **Thunderbolt→PCIe NIC** (e.g. AQC107 `atlantic`), which removes the `r8152` from the shared XHCI. With only 2 ports (1 = power) this means a Thunderbolt PD dock that charges + provides a PCIe NIC; a plain powered USB-C hub would *not* isolate the NIC (still USB Realtek behind the same controller).

## 2026-06-04 (same day, later) — Validation: offload workaround FAILED; reboot cap worked

The minimal TX-offload workaround (`tso`/`tx-tcp6-segmentation`/`gso` off) was deployed ~12:06 and confirmed applied at 12:07:48 (`ethtool -k` showed them off). **With offloads disabled for ~2 hours the box crashed again, identically:**

```
14:16:13 r8152 enp7s0u2u4: NETDEV WATCHDOG: transmit queue 0 timed out 5248 ms
14:16:13 r8152 enp7s0u2u4: Tx timeout
14:16:13 xhci_hcd 0000:07:00.0: xHCI host controller not responding, assume dead
14:16:13 xhci_hcd 0000:07:00.0: HC died; cleaning up
14:16:42 WARNING: Pool 'firstpool' has encountered an uncorrectable I/O failure and has been suspended.
```

**Conclusion: disabling TX segmentation offloads does NOT fix this NIC.** The segmentation engine is not the (sole) trigger — the `r8152` TX path / USB link is flaky more broadly. The cheap software avenue is essentially exhausted.

**The 2-min `reboot.target` cap DID work**, as designed:

```
14:16:42 reset-thunderbolt-xhci: recovery failed; rebooting
14:18:42 reboot.target: Job reboot.target/start timed out → Forcibly rebooting: job timed out   (exactly 2 min)
14:21:25 back up
```

Crash → back-up was **~5 min** (14:16 → 14:21) vs the old ~30+. Keep that change.

**Follow-ups committed:** escalated `r8152-disable-tx-offload` to the maximal set (`tso tx-tcp6-segmentation gso sg tx` off) as a last cheap shot (low odds, since segmentation-off already failed). The offload service auto-ran correctly on the 14:21 boot (the `.device`-unit binding works).

**Recommended permanent fix (equipment):** move Ethernet off USB onto a Thunderbolt **PCIe** NIC so it no longer shares the storage xHCI. With only 2 USB-C ports (one = power), this requires a Thunderbolt PD dock that both charges the Mac and carries a PCIe NIC:

- **OWC Thunderbolt Pro Dock** — 10GbE Aquantia AQC107 (PCIe, kernel `atlantic`), 85 W PD. One cable charges + isolated NIC + USB-A for the DAS, frees the 2nd port. **Top pick** (~$329).
- **CalDigit TS4** — 2.5GbE Realtek RTL8125 (PCIe, `r8169`), 98 W PD, many ports (~$400). 2.5G is plenty for home; confirm the NIC is the PCIe RTL8125.
- A plain powered USB-C hub (even with PD pass-through) would **not** help — its NIC is still a USB Realtek behind the same controller.

After switching, the NIC name changes (PCIe `atlantic` ≠ `enp7s0u2u4`), so update the `IFACE="enp7s0u2u4"` references in `reset-thunderbolt-xhci` and `r8152-disable-tx-offload` (the latter can be removed entirely once the USB NIC is gone).

## 2026-06-05 — Maximal offloads ALSO failed; note the alternate crash signature

The escalated **maximal** offload set (`tso tx-tcp6-segmentation gso sg tx` off) went live ~19:21 on 06-04. The box then crashed **twice more**: 06-04 **19:12** (just before the escalation) and **22:00** (≈2h40m *after* the maximal set was applied). So both the minimal and maximal offload sets FAILED — disabling TX offloads does not stop this NIC. The offload approach is conclusively dead; do not pursue it further.

Crash times on 06-04: 04:41, 14:16, 19:12, 22:00 (four in one day).

**Alternate log signature (important — it fooled a keyword grep).** These two crashes did NOT print `NETDEV WATCHDOG` / `Tx timeout` / `xHCI ... assume dead` / `HC died` / `pool ... suspended`. Instead:

```
19:12:22 r8152 enp7s0u2u4: Tx status -108   (×4)
19:12:22 r8152 enp7s0u2u4: Get ether addr fail
19:12:22 usb 4-2.3: USB disconnect          ← DAS hub
19:12:22 sd [sdb/sde/sda/sdc/sdd] Synchronize Cache(10) failed: DID_ERROR   ← all 5 disks drop
19:12:23 r8152-cfgselector 4-2.4: USB disconnect   ← NIC
```

Same root failure (the whole `usb 4-2` tree — NIC `4-2.4` + DAS hub `4-2.3` + all drives — drops), but the controller was not declared "dead"; the devices just `USB disconnect` with `-108` (ESHUTDOWN). When searching logs for these crashes, grep `Tx status -108|USB disconnect|Get ether addr fail` in addition to the older `Tx timeout|assume dead` strings.

**What went differently (mildly better):** the `reset-thunderbolt-xhci` watchdog caught the NIC-missing within ~2 s and ran `systemctl reboot` (graceful — shows in the journal as `systemd-logind: The system will reboot now!`, which is the watchdog, not a human). The pools did **not** log "suspended" and the reboot hit the 2-min cap, so total downtime was ~3 min instead of ~30. The reboot-cap change is doing its job.

(Correction to the record: a mid-investigation note briefly concluded these two reboots were user-initiated/not crashes — that was wrong, caused by grepping only the old `Tx timeout`/`assume dead` strings. They were the same r8152 USB-tree crash, rebooted by the watchdog.)

**Status:** offload service left deployed but ineffective (revert pending). Decision stands: the only real fix is hardware — move Ethernet to a Thunderbolt **PCIe** NIC (CalDigit TS3 Plus, Intel i210 `igb`, ~$100 used; or OWC TB3 Pro Dock / TS4). See Readme.md.

## 2026-06-12 — The NIC was NOT the (sole) trigger; the wedge is the TB controller itself

**The r8152 root-cause from 06-04 is disproven.** Since then the RTL8153 NIC was **deauthorized** at the
USB level (commit `21c9777`: a udev rule sets `authorized=0` on `0bda:8153` behind hub `05e3:0626`, so
`r8152` never binds — boot log shows `r8152-cfgselector 4-2.4: Device is not authorized for usage`).
With the NIC driver completely out of the picture, **the box wedged again, identically:**

```
Jun 10 16:20  boot; NIC deauthorized at boot (never enumerates)
Jun 11 09:55:55  xhci_hcd 0000:07:00.0: xHCI host controller not responding, assume dead
Jun 11 09:55:55  xhci_hcd 0000:07:00.0: HC died; cleaning up
Jun 11 09:55:55  usb 4-2 / 4-2.2 / ... USB disconnect    (DAS + whole hub tree)
Jun 11 09:55:56  WARNING: Pool 'firstpool' ... suspended
```

The crash happened **during heavy WRITE I/O to the DAS** (`sdd`), with no NIC activity possible. So the
06-04 "100% NIC correlation" was correlation, not causation — the real common factor is the **shared
JHL6540 Thunderbolt controller / the DAS's UAS path under load**, not the Ethernet adapter. A Thunderbolt
PCIe NIC would *not* have prevented this. (The NIC may have been *a* trigger among several, but it is not
necessary.)

**Different signature from the November crashes:** this one logged *only* `assume dead` / `HC died` —
**no** `Unable to change power state from D3hot to D0` / `inaccessible`. Every parent bridge stayed in
`power_state=D0, runtime=active`. So the controller hung while fully powered, not during a PM transition.

### What actually changes when the controller is wedged (all the obvious signals are useless)

Probed live while `firstpool` was suspended (~32 h after the crash — the old watchdog never recovered it):

| sysfs signal | when wedged | useful? |
|---|---|---|
| `/sys/bus/pci/devices/0000:07:00.0` (node exists) | **present** | NO — lingers |
| its `driver` symlink | still `xhci_hcd` | NO |
| `power/runtime_status`, `power_state` | `active`, `D0` (stale) | NO |
| USB root hubs `usb3`/`usb4` | **present** | NO — lingers |
| `/sys/block/sdd` | **present** | NO — lingers |
| **PCI config-space read** of `07:00.0` / `05:0x` | **`ffff ffff`** | **YES** — `8086` when alive |
| `current_link_speed` of `07:00.0` | **`Unknown`** | yes (2nd choice) |
| `/proc/spl/kstat/zfs/<pool>/state` | **`SUSPENDED`** | yes (downstream symptom) |

**Where the link breaks:** reading config space up the chain — `00:1c.4`=`8086`, `04:00.0` (TB upstream
switch)=**`8086` (alive)**, `05:02.0` (its downstream port)=`ffff`, `07:00.0` (xHCI)=`ffff`. So the TB
switch's *host side stays up*; only its **downstream PCIe port (bus 05) drops off the bus**, taking the
xHCI and everything below it. The external `uni` hub + DAS + NIC are collateral, not the cause.

### The PCI-reset recovery DOES work — the old script just never finished it

Contrary to the old "PCI-reset recovery never succeeds" note, a live test recovered the bus **without a
reboot**:

```
echo 1 > /sys/bus/pci/devices/0000:04:00.0/remove   # drop the alive TB upstream switch + its dead subtree
echo 1 > /sys/bus/pci/rescan                          # re-train the link
```

→ the **entire USB tree re-enumerated** (`4-2` hub, `4-2.2` sub-hub, `4-2.2.1..4`, `4-2.4`). The xHCI came
back at a **different PCI BDF** (`07:00.0` gone during the hot state; a cold reboot restores it). The pool
stayed `SUSPENDED` only because `zpool clear` had not been run yet.

**The two real bugs in the old `reset-thunderbolt-xhci`:**
1. **Detection:** `xhci_up()` = `[ -e /sys/bus/pci/devices/0000:07:00.0 ]` was *always true* (the node
   lingers when the HC dies), so the 1-min timer fired and exited 0 forever — the pool sat suspended ~32 h.
   It only ever "worked" when something *else* removed `07:00.0`. (In fact, manually removing `04:00.0`
   during the live test made `07:00.0` vanish, which tripped the old watchdog into rebooting the box — that
   was the reboot during this session, not a fresh crash.)
2. **No `zpool clear`:** it removed the *wrong* nodes (the `05:0x` children + `07:00.0`) instead of the
   alive parent `04:00.0`, and never cleared the suspended pool — so even a good re-enumeration left the
   pool suspended and it always fell through to `systemctl reboot`. That is why it "only ever rebooted."

### New watchdog (this commit)

Rewrote `reset-thunderbolt-xhci` (`configuration.nix`):
- **Detection — device-agnostic, assumes nothing is plugged into the hub:** read PCI config space of the
  stable TB-upstream switch's children (`/sys/bus/pci/devices/0000:04:00.0/0000:*/config`); any `ffff` =
  link wedged. Anchored on `04:00.0` (fixed BDF, directly under PCH root port `00:1c.4`) rather than the
  xHCI's own BDF, which moves after a hot rescan. A `SUSPENDED` pool is kept as a backstop signal.
- **Recovery:** `remove` `04:00.0` → `rescan` → `zpool clear` any suspended pool → re-check; only
  `systemctl reboot` if the link is still `ffff` or a pool is still suspended. This is the no-reboot path
  the old script was missing.

### Reframed permanent fix

The NIC is already neutralized and the wedge persists, so the problem is the **Thunderbolt controller /
DAS USB (UAS) path**, not Ethernet. Avenues worth trying, roughly in order: try the DAS on the *other*
TB port / a different cable; disable UAS for the DAS (`usb-storage.quirks=<vid:pid>:u`) to fall back to
BOT, which some flaky USB-SATA bridges survive; consider replacing the DAS enclosure/cable. The rewritten
watchdog at least auto-heals these wedges in ~1 min instead of leaving the pool suspended indefinitely.

(After this clean reboot `firstpool` is `ONLINE`; it logged 209 transient data errors during the 32 h
suspension — worth a `zpool scrub firstpool`.)
