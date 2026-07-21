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

## Configure tailscale

`services.tailscale` is enabled in configuration.nix (for remote SMB etc.:
the samba `hosts allow` includes the Tailscale CGNAT range 100.64.0.0/10).
Authentication is a one-time manual step after the first deploy:

```
sudo tailscale up
# visit the printed https://login.tailscale.com/a/... URL
# (log in as yonathan@gmail.com)
tailscale status   # verify: shows this node's 100.x address
```

Then in https://login.tailscale.com/admin/machines, disable key expiry for
yonnas so it doesn't drop off the tailnet after 180 days.

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

## Configure Pocket ID (OIDC identity provider)

Pocket ID (modules/pocket-id.nix) is a self-hosted passkey-only OIDC IdP
at https://id.yonathan.org for SSO across Immich, Grafana, Forgejo, and
(eventually) the caddy-security portal. SMB is *not* covered: SMB does
NTLM challenge-response, which no OIDC/LDAP IdP can back, so Samba stays
on local smbpasswd accounts.

1. DNS: Cloudflare CNAME `id.yonathan.org` → `home.yonathan.org`
   (proxy status DNS-only, same as the other subdomains) — created
   2026-07-06 via the API using the caddy DNS-01 token
   (`sudo systemd-creds decrypt --uid=0 /etc/secrets/cloudflare_token.cred -`).
2. Encryption key (encrypts the OIDC signing keys in the SQLite DB at
   /var/lib/pocket-id) — created 2026-07-06:

   ```
   head -c 32 /dev/urandom | base64 | sudo systemd-creds encrypt \
     --name=ENCRYPTION_KEY_FILE - /etc/secrets/pocket_id_encryption_key.cred
   ```

   The `--name` must be `ENCRYPTION_KEY_FILE` (the credential name the
   NixOS module's unit script decrypts). If the key is ever lost, Pocket ID
   cannot read its stored OIDC signing keys; back up /var/lib/pocket-id and
   this cred file together.
3. Deploy (`nas-config/deploy-over-ssh.sh`), then visit
   https://id.yonathan.org/setup to create the initial admin account and
   register its passkey. The page only works while no admin exists.
4. Create each family member in the admin UI and send them a one-time
   access link; opening it logs them in once so they can enroll a passkey
   (Face ID/Touch ID; syncs across their devices via iCloud Keychain).
   The same link flow is the recovery path for lost passkeys.
5. Per app, create an OIDC client in Pocket ID's admin UI, then point the
   app at issuer `https://id.yonathan.org` with that client id/secret:
   - Immich: Admin → Settings → Authentication → OAuth. DONE 2026-07-07
     (Pocket ID client "Immich"). Config: issuer_url
     `https://id.yonathan.org/.well-known/openid-configuration`, the client
     id/secret, scope `openid email profile`, PKCE on (enabled on the
     Pocket ID client too). Callback URLs on the Pocket ID client:
     `https://photos.yonathan.org/auth/login`,
     `https://photos.yonathan.org/user-settings`, and the mobile deep link
     `app.immich:///oauth-callback`. Pocket ID accepts the custom scheme,
     so the Mobile Redirect URI Override is NOT needed (that override is
     only for providers like Google that reject custom schemes). Auto
     register is left on — the IdP is the gate, and OAuth links to the
     existing admin by matching email (yonathan@gmail.com). The client
     secret lives only in Immich's DB (system-config) + Pocket ID, not in
     Nix. Gotchas: (a) the secret is shown once at creation — if you
     mistype it, "Invalid client secret" appears in immich-server logs;
     use "Create new client secret" on the Pocket ID client to regenerate.
     (b) new Pocket ID clients default to restricted with no groups; click
     Unrestrict.
   - Grafana: `services.grafana.settings."auth.generic_oauth"` in
     home-monitoring.nix — DONE 2026-07-07 (client "Grafana"). Both the
     client id and secret are manual creds referenced by `$__file{}` (see
     "client id vs client secret" above); create them after the Pocket ID
     client exists. The id is not secret → plaintext file; the secret →
     encrypted:

     ```
     # id (public): plaintext credential
     printf %s '<client-id-uuid>' | ssh home.yonathan.org -- \
       "sudo tee /etc/secrets/grafana_oauth_client_id >/dev/null"
     # secret (never on local disk): copy from Pocket ID, then
     pbpaste | ssh home.yonathan.org -- \
       "sudo systemd-creds encrypt --name=grafana_oauth_client_secret - \
        /etc/secrets/grafana_oauth_client_secret.cred"
     ```

     Gotcha: if Pocket ID shows "You're not allowed to access this service",
     the client is in restricted mode with no Allowed User Groups; click
     Unrestrict on the client page.
   - Forgejo: DONE 2026-07-07. Two parts:
     (a) Account-linking behaviour is declarative in modules/forgejo.nix
         ([oauth2_client] ACCOUNT_LINKING=auto, USERNAME=preferred_username).
     (b) The auth *source* is stored in Forgejo's DB (not Nix), added at
         Site Administration → Identity & access → Authentication sources →
         Add → OAuth2 → provider "OpenID Connect", name "pocket-id" (this
         name is the callback slug: /user/oauth2/pocket-id/callback), the
         client id/secret, and auto-discovery URL
         `https://id.yonathan.org/.well-known/openid-configuration`.
     Gotcha: Forgejo requests ONLY `openid` by default, so its login lands
     on an empty "register/link" page. You MUST set the source's scopes to
     `openid email profile` (Additional scopes field, or CLI
     `forgejo admin auth update-oauth --id <n> --scopes openid --scopes
     email --scopes profile`) and restart Forgejo so it re-reads them.
     First OIDC login for an existing account (e.g. yonran) requires a
     one-time password confirmation on the "Link to an existing account"
     tab (Forgejo confirms ownership before attaching the external
     identity); after that, SSO is seamless. The source persists in the
     ZFS-backed DB across redeploys, but the scopes fix is NOT in Nix
     (auth sources can't be) — recreate it with the scopes above if the DB
     is ever lost.
   - caddy-security (portal for prometheus + unlock): Pocket ID added as a
     second `generic` OIDC provider alongside google — DONE 2026-07-09
     (client "caddy-security"). Config in configuration.nix `security {}`:
     `driver generic`, `metadata_url` auto-discovery, and crucially
     `delay_start`/`retry_*` because Pocket ID is proxied by this SAME caddy
     — a synchronous discovery fetch during Provision() would dead-lock caddy
     startup (greenpau/caddy-security#282). id/secret are creds
     (`caddy_pocketid_client_{id,secret}`, id plaintext, secret encrypted).
     Callback slug is the provider name: `/auth/oauth2/pocketid/
     authorization-code-callback` (registered on the client for both the
     prometheus and unlock hosts, since the portal is served per-host at
     /auth). Both providers are enabled during the transition; retire google
     (drop `oauth identity provider google`, its `enable` line, and the
     google_client_* creds/env) once Pocket ID login is confirmed.
     Note: after OAuth login the portal lands on /auth/portal (its home)
     rather than bouncing back to the original app — caddy-security does not
     preserve the redirect_url across the IdP round-trip; re-open the app URL
     to proceed. Optional `ui { link ... }` tiles make that page useful.

### client id vs client secret

Each Pocket ID client has a **client id** (a random UUID Pocket ID assigns)
and a **client secret**, and Pocket ID 2.x has no declarative client config —
both are minted by the IdP and stored only in its DB. So neither is a
reproducible value: hard-coding the id in Nix would only ever be correct
against *this* machine's Pocket ID DB (a from-scratch rebuild mints a
different UUID and the hard-coded id would point at nothing). The id is *not*
confidential — it rides in the browser redirect — but because it is
IdP-issued, non-reproducible state, it is kept out of Nix as a matched pair
with the secret — but loaded per confidentiality: the **id** is a plaintext
`LoadCredential` file (no point encrypting a public value into an opaque blob
you can't `cat`), the **secret** is `LoadCredentialEncrypted` (systemd-creds).
Both reach the app via `$__file{}` (Grafana, caddy) or are entered together
in the app's own DB (Immich, Forgejo); Nix references them by path only. If
the Pocket ID DB is lost and clients are recreated, every app's id *and*
secret must be re-created together with the new values.

### Rotating a client secret

Pocket ID reveals a client secret **once**, at (re)generation — reload the
page and it is masked forever after, so you must capture it immediately.
To rotate: open the client at
`https://id.yonathan.org/settings/admin/oidc-clients/<client-id>`, click the
↻ icon next to "Client secret" → **Generate**, then place the new value.
Until both sides match, *new* SSO logins to that app fail (existing sessions
keep working), so place-and-restart promptly.

- Grafana (secret in a NAS cred file) — copy the new value, then, without it
  ever touching disk locally, pipe it straight into the encrypted cred and
  restart (done this way 2026-07-08):

  ```
  pbpaste | ssh home.yonathan.org -- \
    "sudo systemd-creds encrypt --name=grafana_oauth_client_secret - \
     /etc/secrets/grafana_oauth_client_secret.cred && sudo systemctl restart grafana"
  ```

  The `--name` must equal the LoadCredentialEncrypted id
  (`grafana_oauth_client_secret`, see home-monitoring.nix). caddy-security's
  secret rotates the same way: `--name=caddy_pocketid_client_secret`, file
  `/etc/secrets/caddy_pocketid_client_secret.cred`, restart `caddy` (its
  client id is the plaintext `/etc/secrets/caddy_pocketid_client_id`). The
  `caddy_`/`grafana_` service prefix disambiguates /etc/secrets, where every
  app has a "pocketid client secret".
- Immich (secret in Immich's DB): paste into Admin → Settings →
  Authentication → OAuth → Client Secret, Save.
- Forgejo (secret in Forgejo's DB): paste into Site Administration →
  Identity & access → Authentication sources → `pocket-id` → Client Secret,
  Save (restart Forgejo to be safe).
- rustdesk-api (secret in rustdesk-api's own DB, no NixOS config involved):
  paste into its admin panel → OAuth Management → the Pocket ID provider
  entry → Client Secret, Save.

Warning: passkeys are bound to the hostname (WebAuthn RP ID). Renaming
id.yonathan.org invalidates every enrolled passkey.

## Configure RustDesk (self-hosted relay + API/admin server)

RustDesk's OSS `hbbs`/`hbbr` (services.rustdesk-server) provide the
ID/relay servers — TCP/UDP on ports 21115-21117, DNAT'd straight through
by the router, never touching Caddy. `rustdesk-api`
(modules/rustdesk-api.nix, https://github.com/lejianwen/rustdesk-api) adds
the account/admin-console layer official RustDesk only ships as paid
Server Pro: a web admin console (device list, login/connection/file-transfer
audit logs), accounts, and address-book sync. All three (ID server, relay
server, API server) share one hostname, `rustdesk.yonathan.org` — a DNS
name doesn't care which port it's used with, and the API server (HTTPS,
Caddy-routed by hostname) and the raw hbbs/hbbr ports coexist on it with
zero extra DNS/router config, since the existing `*.yonathan.org` wildcard
already covers it.

Auth is native to rustdesk-api itself (not Caddy's `authorize with
mypolicy` layer) — password login now, OIDC-only via Pocket ID once
bootstrapped. Order matters below: the JWT secret must exist before the
container's systemd unit can start, and password login must stay on just
long enough to wire up OIDC, or you lock yourself out.

1. Before the first deploy, on the NAS, generate and encrypt the JWT
   signing key:

   ```
   head -c 32 /dev/urandom | base64 | sudo systemd-creds encrypt \
     --name=rustdesk_api_jwt_key - /etc/secrets/rustdesk_api_jwt_key.cred
   ```

2. Deploy (`nas-config/deploy-over-ssh.sh`) with
   `services.rustdesk-api.disablePwdLogin = false` (the default). Then
   `podman logs rustdesk-api` once to capture the auto-generated initial
   admin password.
3. Log into `https://rustdesk.yonathan.org/_admin/` with that password;
   change it.
4. In Pocket ID, create an OIDC client for `rustdesk-api`, redirect URI
   `https://rustdesk.yonathan.org/api/oidc/callback`.
5. In rustdesk-api's admin panel (OAuth Management), add an OIDC provider:
   issuer `https://id.yonathan.org`, the client id/secret from step 4,
   scopes `openid,email,profile`, and turn on **AutoRegister** — a
   first-time OIDC login then auto-creates the local (always non-admin)
   rustdesk-api account, no separate pre-created account needed. Since
   Pocket ID has no open self-registration, this doesn't reopen anything;
   adding a new person only ever means creating them in Pocket ID.
6. Bind your own admin account to your Pocket ID identity (the "bind" flow
   from step 5) and confirm OIDC login works end-to-end for it.
7. On each RustDesk desktop client you want synced, set **API Server** =
   `https://rustdesk.yonathan.org` (in addition to the ID/Relay/Key already
   configured), then log in via **username/password** (the account and
   password were auto-created when you first logged into the admin console
   via OIDC in step 6).
8. (Optional: if you want OIDC-only login to the web admin console and don't
   need desktop clients to connect via API Server, set
   `services.rustdesk-api.disablePwdLogin = true` and redeploy. This breaks
   desktop-client login — leave it false if you want clients to work. With it
   false, Pocket ID still gates *account creation* via AutoRegister; password
   is just how desktop clients authenticate once their account exists.)

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

## Configure Immich external library (gphotos-sync)

Immich (modules/immich.nix) mounts `/firstpool/family/photos` read-only at
`/external`. The **gphotos-sync** tool (google-photos-tools repo, `sync/`)
writes Google Photos originals + XMP sidecars into `photos/google` over the
`photos` SMB share (configuration.nix) and triggers Immich scans via API.

One-time manual setup (done 2026-07-07):

1. Created the external library via the API (Immich has no NixOS-declarative
   config for libraries; equivalently: Administration → External Libraries):

   ```
   curl -X POST -H "x-api-key: $ADMIN_KEY" -H 'content-type: application/json' \
     -d '{"ownerId":"<admin user id from GET /api/users/me>",
          "name":"Google Photos","importPaths":["/external/google"]}' \
     http://yonnas:2283/api/libraries
   # -> id 99c590c3-7cce-439a-92a8-8eda92a53dc4 (in gphotos-sync.config.json)
   ```

2. Created a scoped API key for the sync (User Settings → API Keys, as the
   admin user — `/libraries` routes require an admin): permissions
   `asset.upload`, `library.read`, `library.update`, `album.read`,
   `album.create`, `albumAsset.create`. See the permission table in
   google-photos-tools `sync/README.md`.

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
