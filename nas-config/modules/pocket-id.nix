# Pocket ID: self-hosted OIDC identity provider with passkey-only login.
# Purpose: single sign-on for the OIDC-capable apps (Immich, Grafana,
# Forgejo, and eventually the caddy-security portal in place of Google).
# SMB stays on local smbpasswd accounts (SMB does NTLM challenge-response,
# which no OIDC/LDAP IdP can back).
#
# Reverse-proxied by Caddy at https://id.yonathan.org (see configuration.nix).
#
# One-time setup after first deploy:
# 1. Create the encryption key (encrypts the OIDC signing keys in the
#    SQLite DB at /var/lib/pocket-id):
#      head -c 32 /dev/urandom | base64 | sudo systemd-creds encrypt \
#        --name=ENCRYPTION_KEY_FILE - /etc/secrets/pocket_id_encryption_key.cred
# 2. Visit https://id.yonathan.org/setup to create the initial admin
#    account and register its passkey (the page only works while no admin
#    exists yet).
# 3. Create the other users in the admin UI and send each a one-time
#    access link; opening it logs them in once so they can enroll their
#    passkey. The same link flow is the recovery path for lost passkeys.
# 4. Per app, create an OIDC client in the admin UI and configure the app
#    with the issuer https://id.yonathan.org plus that client id/secret.
#    (Immich mobile: also set its Mobile Redirect URI Override to
#    https://photos.yonathan.org/api/oauth/mobile-redirect and register
#    that as a callback URL on the Pocket ID client.)
#
# NOTE: passkeys are bound to the hostname (WebAuthn RP ID). Renaming
# id.yonathan.org would invalidate every enrolled passkey.
{ config, lib, pkgs, ... }:

{
  services.pocket-id = {
    enable = true;
    settings = {
      APP_URL = "https://id.yonathan.org";
      TRUST_PROXY = true; # behind Caddy
      ANALYTICS_DISABLED = true;
      # Loopback only; Caddy terminates TLS and proxies to this port.
      HOST = "127.0.0.1";
      PORT = 1411;
    };
    # This generates a LoadCredential entry named ENCRYPTION_KEY_FILE and an
    # `export ENCRYPTION_KEY=$(systemd-creds cat ENCRYPTION_KEY_FILE)` in the
    # unit script...
    credentials.ENCRYPTION_KEY = "/etc/secrets/pocket_id_encryption_key.cred";
  };

  # ...but the file on disk is systemd-creds encrypted (same convention as
  # caddy's /etc/secrets/*.cred), which plain LoadCredential= passes through
  # without decrypting. Re-declare it as LoadCredentialEncrypted= under the
  # same credential name so the module's export still finds it decrypted.
  systemd.services.pocket-id.serviceConfig = {
    LoadCredential = lib.mkForce [ ];
    LoadCredentialEncrypted = [
      "ENCRYPTION_KEY_FILE:/etc/secrets/pocket_id_encryption_key.cred"
    ];
  };
}
