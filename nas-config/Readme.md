This is the NixOS config for a home server using a 2015 Macbook Pro.

## NixOS Installation steps:

1. Download Minimal ISO Image from [NixOS ISOs](https://nixos.org/download#nixos-iso):
Minimal ISO Image
([NixOS Manual: Installation: Obtaining NixOS](https://nixos.org/manual/nixos/stable/#sec-obtaining)).
2. Copy ISO to a flash disk using
`sudo dd if=/tmp/nixos-minimal-VERSION-linux.iso  of=/dev/rdiskNN bs=4M conv=fsync status=progress`
([NixOS Manual: Installation: Additional installation notes: Booting from a USB flash drive](https://nixos.org/manual/nixos/stable/#sec-booting-from-usb)).
**Add `status=progress`** to show status bar in gnu coreutils 8.24+.
3. Plug in Thunderbolt to **Ethernet adapter** because the ISO does not have
the nonfree wifi adapter `config.boot.kernelPackages.broadcom_sta` enabled.
4. Boot from USB stick
([NixOS Manual: Installation: Booting from the install medium](https://nixos.org/manual/nixos/stable/#sec-installation-booting)).
5. Partition the SSD
([NixOS Manual: Installation: Partitioning and formatting](https://nixos.org/manual/nixos/stable/#sec-installation-manual-partitioning))
  ```
  sudo parted /dev/nvme0n1 -- print
  # remove the MacOS partition 2. No need to repartition 1 (EFI System Partition)
  sudo parted /dev/nvme0n1 -- rm 2
  sudo parted /dev/nvme0n1 -- mkpart root ext4 211MB -16GB
  sudo parted /dev/nvme0n1 -- mkpart swap linux-swap -16GB 100%
  ```
6. Format the SSD
([NixOS Manual: Installation: Partitioning and formatting](https://nixos.org/manual/nixos/stable/#sec-installation-manual-partitioning)).
  ```
  # No need to reformat partition 1 (EFI System Partition) which is already FAT
  sudo mkfs.ext4 -L nixos /dev/nvme0n1p2
  sudo mkswap -L swap /dev/nvme0n1p3
  ```
7. Mount big partition to `/mnt`, UEFI partition to `/mnt/boot`
([NixOS Manual: Installation: Installing](https://nixos.org/manual/nixos/stable/#sec-installation-manual-installing)).
  ```
  mount /dev/nvme0n1p2 /mnt
  mount /dev/nvme0n1p1 /mnt/boot
  ```
8. Create /mnt/etc/nixos/hardware-configuration.nix and /mnt/etc/nixos/configuration.nix
([NixOS Manual: Installation: Installing](https://nixos.org/manual/nixos/stable/#sec-installation-manual-installing)).
  ```
  nixos-generate-config
  ```
9. Edit `/mnt/etc/nixos/configuration.nix`: add `nixpkgs.config.allowUnfree = true`
so that broadcom_sta module can load
10. Install NixOS packages `nixos-install`
([NixOS Manual: Installation: Installing](https://nixos.org/manual/nixos/stable/#sec-installation-manual-installing))
11. Change `configuration.nix` to allow SSHing to machine and then run
`sudo nixos-rebuild switch`:
  * Set `networking.hostName = "yonnas";` to something unique
  * Enable SSH server
    ```
    services.openssh.enable = true;
    services.openssh.settings.PasswordAuthentication = true;
    ```
  * Define a non-root user (by default, SSH does not allow root password ssh)
    ```
    users.users.yonran = {
      isNormalUser = true;
      extraGroups = [ "wheel" ]; # Enable ‘sudo’
    }
    ```
  * Enable Bonjour mDNS so you can discover yonnas.local
    ```
    services.avahi.enable = true;
    services.avahi.publish = {
      enable = true;
      addresses = true; # publish the IP address of this machine
      workstation = true; # publish the machine as a workstatino, which includes the hostname
    };
    ```
  * Enable wifi
    ```
    networking.networkmanager.enable = true;
    ```
12. Set a password for the non-root user (`sudo passwd yonran`)
13. Join a network:
  ```
  nmcli device wifi list
  sudo nmcli connection add con-name NAME type wifi ssid SSID
  sudo nmcli connection up NAME --ask
  ```
14. Then use another machine to `ssh yonran@yonnas.local` and do the rest remotely.
  ```
  ./deploy-over-ssh.sh
  ```

## Deploying changes

From a workstation with SSH access, push the local `nas-config/` to the NAS and rebuild:

```
./deploy-over-ssh.sh
```

This rsyncs `nas-config/` to `/etc/nixos/` on `yonran@home.yonathan.org` (via `sudo rsync`,
excluding `hardware-configuration.nix`) and runs `sudo nixos-rebuild switch`. To verify a change
builds without activating it, run `sudo nixos-rebuild dry-build` on the NAS instead.

For ad-hoc diagnosis, `ssh yonran@home.yonathan.org` and use `journalctl`, `zpool status`,
`systemctl`, and sysfs under `/sys/bus/pci|usb/...`.

## Configure caddy

To configure Let’s Encrypt ACME DNS-01 wildcard certificate,
we need a CloudFlare token.

Create a secret at https://dash.cloudflare.com/profile/api-tokens.

```
sudo mkdir -p /etc/secrets
sudo systemd-creds encrypt --uid=0 - /etc/secrets/cloudflare_token.cred
# (paste the token, then enter, then Ctrl+D)
```

Create [caddy-security OAuth2](https://docs.authcrunch.com/docs/authenticate/oauth/backend-oauth2-0002-google) keys.
Create OAuth 2.0 Client ID at https://console.cloud.google.com/apis/credentials?project=yontriggers

* configure Authorized redirect URIs (one per OIDC-protected subdomain):
  - `https://prometheus.yonathan.org/auth/oauth2/google/authorization-code-callback`
  - `https://unlock.yonathan.org/auth/oauth2/google/authorization-code-callback`
* `sudo systemd-creds encrypt --tpm2-device=auto - /etc/secrets/google_client_id`
* `sudo systemd-creds encrypt --tpm2-device=auto - /etc/secrets/google_client_secret`
* `uuidgen | tr -d '\n' | sudo systemd-creds encrypt --name auth_sign_key --tpm2-device=auto - /etc/secrets/caddy_auth_sign_key.cred`

## Configure sb-exporter

To configure the monitoring of the cable sb-exporter modem monitor,
add a systemd EnvironmentFile to /etc/sb-exporter.env:

```
MODEM_PASSWORD=password
```

## Configure owntracks-recorder

To configure owntracks-recorder, we need to create
`/etc/default/ot-recorder`

```
# Note that OTR_STORAGEDIR is default /var/spool/owntracks/recorder/store;
# we copy from there to /firstpool/family/owntracks/recorder/store later

# https://opencagedata.com/dashboard account with username yonathan@gmail.com
OTR_GEOKEY="opencage:xxxxxxxxxxxxx"
```

And create the data directories:

```
mkdir -p /firstpool/family/owntracks/recorder/store
chmod o+x /firstpool/family
sudo chgrp -R owntracks-recorder /firstpool/family/owntracks
```

## Monitoring and Email Alerts

This repo configures a local monitoring stack and email alerting for disk space, SMART, and ZFS events.

- Prometheus + node_exporter + blackbox_exporter + sb-exporter (cable modem).
- Grafana on `http://<nas-ip>:3000` (default admin/admin, then change password).
- Alertmanager routes alerts to email via a local Postfix MTA.
- ZFS ZED emails on zpool events.

Configuration entry points
- `nas-config/home-monitoring.nix`: Prometheus, Grafana, exporters (enabled in `configuration.nix`).
- `nas-config/modules/email.nix`: Local Postfix relay (e.g., to Gmail on 587).
- `nas-config/home-monitoring.nix`: Prometheus, Grafana, exporters, Alertmanager, ZFS ZED, alert rules.

What is enabled by default
- In `nas-config/configuration.nix`:
  - `services.home-monitoring.enable = true;`
  - `services.alertingEmail.enable = true;` (local Postfix)
  - `services.home-monitoring.alertEmail = { to = ..., from = ..., smtpSmarthost = "127.0.0.1:25"; }`
  - Email: Alertmanager uses the local Postfix which relays to Gmail on port 587.
  - Disk-free alert threshold: 1 GiB available (5m sustained) on non-ephemeral filesystems.

One-time Gmail setup (required)
1) Create a Gmail App Password
   - Google Account → Security → 2‑Step Verification → [App passwords](https://myaccount.google.com/apppasswords) → App: Mail → Device: Other (e.g., "Postfix").

2) Add SMTP credentials on the NAS (root-only, not in Git)
   - Create `/etc/postfix/sasl_passwd` with mode 0600:
     ```
     # this file is used as a smtp_sasl_password_maps texthash input
     # https://www.postfix.org/postconf.5.html#smtp_sasl_password_maps
     # for file format see https://www.postfix.org/postmap.1.html
     [smtp.gmail.com]:587 yonathan@gmail.com:APP_PASSWORD_HERE
     ```
   - Reload Postfix:
     ```
     sudo systemctl reload postfix
     ```

3) Rebuild NixOS
   ```
   sudo nixos-rebuild switch
   ```

How to test email delivery
- Simple sendmail test:
  ```
  printf "Subject: test via Gmail relay\n\nhello\n" | sendmail -v yonathan@gmail.com
  ```
- Alertmanager path (should email via Gmail relay):
  ```
  curl -s -XPOST localhost:9093/api/v2/alerts \
    -H 'Content-Type: application/json' \
    -d '[{"labels":{"alertname":"TestEmail"},"annotations":{"summary":"test"}}]'
  ```

Services and status
- Check status/logs:
  ```
  systemctl status postfix zed alertmanager prometheus grafana
  journalctl -u postfix -u zed -u alertmanager -e
  ```

Disk-space alert details
- Rule fires when available bytes < 1,073,741,824 (1 GiB) for 5 minutes.
- Excludes tmpfs, devtmpfs, overlay, /run, /boot, and /nix/store.
- Adjust threshold in `services.alertingEmail.diskFreeBytesThreshold` (bytes).

ZFS alerts
- ZED: emails on pool state changes, errors, resilver/scrub events, etc.

Notes
- Postfix listens on localhost only; nothing is exposed externally.
- Outbound port 25 is blocked on residential cable; we relay via Gmail on port 587.
- From/Envelope are rewritten to `yonathan@gmail.com` for Gmail acceptance.

## Jellyfin

Jellyfin is enabled and listening on the default HTTP port:

- UI: `http://<nas-ip>:8096`
- Firewall: ports 8096 (HTTP) and 8920 (HTTPS) are opened
- HW accel: VAAPI is enabled via `video`/`render` groups and OpenGL VAAPI drivers

First-time setup
- Visit the UI, create an admin user, and add your libraries.
- Suggested paths: `/firstpool/family/media/<Movies|TV|Music|Photos>` (already shared via Samba as "public").
- Metadata defaults to Jellyfin’s data dir; you don’t need write access to media folders unless you choose to save artwork alongside media.

Notes
- If using Intel iGPU, the config includes `intel-media-driver` and `vaapiIntel` for older gens.
- For AMD/NVIDIA, you may adjust `hardware.opengl.extraPackages` accordingly.

## Known issue: USB NIC / xHCI wedge crashes

The server (`MacBookPro14,1`) has only two Thunderbolt 3 / USB-C ports — one is power. Both the
TerraMaster D5-300C USB DAS and the Realtek RTL8153 USB Ethernet adapter (`enp7s0u2u4`, driver
`r8152`) sit behind one bus-powered USB-C hub on the machine's single JHL6540 controller, so they
share one xHCI.

Symptom: the Thunderbolt xHCI periodically wedges (`xhci_hcd 0000:07:00.0 ... assume dead` /
`HC died`); all USB devices drop; the ZFS pool(s) on the DAS suspend (`failmode=wait`); the box
either hangs ~30 min on the un-syncable pools at the next reboot (capped to 2 min, below) or sits
with the pool suspended until the watchdog recovers it. After a reboot the encrypted dataset is
locked again and must be re-unlocked (see the zfs-unlock web UI).

**Root cause (updated 2026-06-12):** *not* the NIC, despite the strong 06-04 correlation. After the
RTL8153 was deauthorized (commit `21c9777`, so `r8152` never binds), the box wedged again identically
— during DAS write I/O, with the NIC out of the loop. Config-space probing shows the **TB switch's
downstream PCIe port (bus `05`) drops off the bus** while the upstream switch `04:00.0` stays alive;
the fault is the **Thunderbolt controller / DAS USB (UAS) path**, not Ethernet. Full evidence chain,
the disproven `r8152` mechanism, and the live recovery test are in `../crashes.md` (2026-06-12 entry).

Mitigations in `configuration.nix`:
- `reset-thunderbolt-xhci` service + timer — **auto-heals the wedge** (rewritten 2026-06-12). Detects
  it device-agnostically by reading PCI config space of the stable TB-upstream switch's children
  (`ffff` = link down — node presence/driver/power-state all linger and are useless), then recovers
  by `remove`+`rescan` of `0000:04:00.0` followed by `zpool clear`, only rebooting if that fails. The
  old version checked for the xHCI node's presence (always true → never fired) and never ran
  `zpool clear` (so it only ever rebooted).
- `reboot.target` job timeout cut from the 30-min default to 2 min — **confirmed working**: a crash
  recovered in ~5 min instead of ~30 (`JobTimeoutAction=reboot-force` is the systemd default; we only
  shortened the timer). Healthy reboots are unaffected. Keep.
- `systemd.services.r8152-disable-tx-offload` — disabled TX offloads on `enp7s0u2u4`. **FAILED** (both
  minimal and maximal sets) and now moot, since the NIC is deauthorized. Vestigial; remove with the
  NIC config.

Things to try (the fault is the TB controller / DAS USB path, so a Thunderbolt PCIe NIC would *not*
fix it): move the DAS to the other TB port / a different cable; disable UAS for the DAS
(`usb-storage.quirks=<vid:pid>:u`, forcing BOT, which some flaky USB-SATA bridges survive); or replace
the DAS enclosure. The Ethernet adapter is already neutralized, so the earlier "buy a Thunderbolt PCIe
NIC" recommendation no longer addresses the crash.
