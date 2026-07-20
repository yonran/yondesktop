# rustdesk-api: self-hosted, OIDC-gated web console + account/API server for
# the RustDesk relay (services.rustdesk-server / hbbs+hbbr, see configuration.nix).
# Upstream (official RustDesk) only ships this role as paid, closed-source
# Server Pro. This deploys the open-source reimplementation
# https://github.com/lejianwen/rustdesk-api as a Podman container.
#
# Gives: a real admin console (device list, login/connection/file-transfer
# audit logs), accounts, and address-book sync — none of which the bare
# hbbs/hbbr peer table provides (it only ever stores {id, uuid, pk,
# created_at, last-seen ip}, no admin API).
#
# Auth model: OIDC is configured INSIDE the app itself against Pocket ID
# (id.yonathan.org), not via Caddy's caddy-security layer — same posture as
# Immich/Jellyfin/Forgejo/Home Assistant/Pocket ID itself elsewhere in this
# Caddyfile (Caddy does TLS + rate-limits the login endpoint, the app owns
# its own auth). Password login is disabled once OIDC is confirmed working
# (see step-by-step setup below), so Pocket ID becomes the only way in.
#
# One-time setup (order matters — the secret must exist before the unit can
# start, and password login must stay on just long enough to bootstrap OIDC
# or you lock yourself out):
#
# 1. Before the first deploy, on the NAS, generate and encrypt the JWT
#    signing key (systemd's LoadCredentialEncrypted fails the unit at start
#    if the file doesn't exist yet):
#      head -c 32 /dev/urandom | base64 | sudo systemd-creds encrypt \
#        --name=rustdesk_api_jwt_key - /etc/secrets/rustdesk_api_jwt_key.cred
# 2. Deploy with services.rustdesk-api.disablePwdLogin = false (the
#    default). Then `podman logs rustdesk-api` once to capture the
#    auto-generated initial admin password (same bootstrap pattern as
#    Immich/Pocket ID).
# 3. Log into https://rustdesk.yonathan.org/_admin/ from LAN/Tailscale with
#    that password; change it.
# 4. In Pocket ID (id.yonathan.org), create a new OIDC client for
#    rustdesk-api, redirect URI
#    https://rustdesk.yonathan.org/api/oidc/callback.
# 5. In rustdesk-api's admin panel (OAuth Management), add an OIDC provider
#    entry: issuer https://id.yonathan.org, the client id/secret from step
#    4, scopes openid,email,profile, and turn on AutoRegister for this
#    provider. With AutoRegister on, a first-time OIDC login auto-creates
#    the local rustdesk-api account on the spot (always non-admin) — no
#    separate pre-created account needed. Since Pocket ID itself has no
#    open self-registration (see modules/pocket-id.nix), AutoRegister
#    doesn't reopen anything; it's enforced once instead of twice. Net
#    effect: adding a new person only ever means creating them in Pocket
#    ID — no second rustdesk-api account-creation step.
# 6. Bind your own admin account to your Pocket ID identity (the "bind"
#    flow from step 5) and confirm OIDC login works end-to-end for it —
#    do this BEFORE the next step, or you'll lock yourself out.
# 7. Now set services.rustdesk-api.disablePwdLogin = true and redeploy.
#    Password login is off entirely; OIDC via Pocket ID is the only way
#    in, for the admin and everyone else.
# 8. On each RustDesk client you want synced, set API Server =
#    https://rustdesk.yonathan.org (in addition to the ID/Relay/Key
#    already configured), then log in via the OIDC option.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.rustdesk-api;
  rustdeskCfg = config.services.rustdesk-server;
  relayHost = lib.head rustdeskCfg.signal.relayHosts;
in
{
  options.services.rustdesk-api = {
    enable = lib.mkEnableOption "self-hosted RustDesk API/admin server (lejianwen/rustdesk-api)";

    disablePwdLogin = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Disable password login entirely (OIDC-only). Leave false for the
        initial bootstrap (see module header); flip to true only after
        confirming OIDC login works for the admin account, or you will
        lock yourself out.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.podman.enable = true;

    virtualisation.oci-containers = {
      backend = "podman";
      containers.rustdesk-api = {
        image = "docker.io/lejianwen/rustdesk-api:v2.7";

        ports = [ "127.0.0.1:21114:21114" ];

        volumes = [
          "/firstpool/family/rustdesk-api:/app/data"
        ];

        environmentFiles = [ "/run/rustdesk-api-jwt.env" ];

        environment = {
          RUSTDESK_API_LANG = "en";
          RUSTDESK_API_RUSTDESK_ID_SERVER = "${relayHost}:21116";
          RUSTDESK_API_RUSTDESK_RELAY_SERVER = "${relayHost}:21117";
          RUSTDESK_API_RUSTDESK_API_SERVER = "https://${relayHost}";
          # Existing hbbs public key (--key _ managed keypair) — safe to
          # embed, it's the same value already handed to clients manually.
          RUSTDESK_API_RUSTDESK_KEY = "HmeG5ZldPtedY0PoEqATxw5Dj30XNCdb0k66QJ0yfGI=";
          # Public password self-registration form off (separate from OIDC
          # AutoRegister, see module header step 5).
          RUSTDESK_API_APP_REGISTER = "false";
          RUSTDESK_API_APP_DISABLE_PWD_LOGIN = lib.boolToString cfg.disablePwdLogin;
          # Without this the app sees every client as 127.0.0.1 behind Caddy,
          # collapsing its own internal login-limiter/audit-log IPs.
          RUSTDESK_API_GIN_TRUST_PROXY = "127.0.0.1";
        };

        extraOptions = [ "--network=podman" ];

        dependsOn = [ ];
      };
    };

    # JWT signing key: systemd-encrypted credential (see module header step
    # 1), decrypted into an env-file podman can consume (oci-containers
    # needs a real KEY=value file, not a raw secret blob). Not a bypass if
    # left unset (the app falls back to opaque DB-checked tokens) but a
    # real signing key is standard defense-in-depth.
    systemd.services.podman-rustdesk-api = {
      requires = [ "firstpool-family.mount" "network-online.target" ];
      after = [ "firstpool-family.mount" "network-online.target" ];
      partOf = [ "firstpool-family.mount" ];
      wantedBy = [ "firstpool-family.mount" ];
      unitConfig.RequiresMountsFor = "/firstpool/family";

      serviceConfig = {
        LoadCredentialEncrypted = [
          "rustdesk_api_jwt_key:/etc/secrets/rustdesk_api_jwt_key.cred"
        ];
      };

      preStart = ''
        set -eu
        echo "RUSTDESK_API_JWT_KEY=$(cat "$CREDENTIALS_DIRECTORY/rustdesk_api_jwt_key")" > /run/rustdesk-api-jwt.env
        chmod 0600 /run/rustdesk-api-jwt.env
      '';
    };
  };
}
