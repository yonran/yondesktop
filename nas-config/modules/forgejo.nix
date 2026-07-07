# forgejo.nix — self-hosted git forge at https://git.yonathan.org
#
# Purpose: source of truth for family repos (first user: noel-site, the
# noelsirivansanti.com website), with Forgejo Actions CI deploying to
# Cloudflare Workers on push. Sveltia CMS (served on the website at /admin)
# talks to Forgejo's API from the browser as its git backend, which is why
# CORS is enabled for the site origin below.
#
# Data lives on ZFS (/firstpool/family/forgejo) so it is covered by the
# existing zfs-backup-module snapshots to backuppool.
#
# ---------------------------------------------------------------------------
# MANUAL (non-declarative) setup — everything done by hand on 2026-07-05/06.
# Redo these if the state dir or /etc/secrets is ever lost. The forgejo CLI
# needs the env vars shown or it reads the wrong config:
#   BIN=$(systemctl cat forgejo | grep ExecStart= | sed 's/ExecStart=//; s/ .*//')
#   FJ() { sudo -u forgejo env GITEA_WORK_DIR=/firstpool/family/forgejo \
#          GITEA_CUSTOM=/firstpool/family/forgejo/custom "$BIN" "$@"; }
#
# 1. State dir (before first start; the module's bootstrap fails without it):
#      sudo mkdir -p /firstpool/family/forgejo/custom/conf
#      sudo chown -R forgejo:forgejo /firstpool/family/forgejo
#      sudo chmod 750 /firstpool/family/forgejo
# 2. Admin user (registration is disabled, so users are created here):
#      FJ admin user create --admin --username yonran --email yonathan@gmail.com --random-password
#    (initial random password was changed after first login)
# 3. Actions runner registration token (the gitea-runner-nas service reads it):
#      FJ actions generate-runner-token
#      echo "TOKEN=<token>" | sudo tee /etc/secrets/forgejo-runner-token
#      sudo chmod 600 /etc/secrets/forgejo-runner-token
#      sudo systemctl restart gitea-runner-nas
# 4. Public DNS record git.yonathan.org CNAME home.yonathan.org: created
#    imperatively in the yonathan.org Cloudflare zone (grey-cloud) with the
#    caddy DNS-01 token from /etc/secrets/cloudflare_token.cred. The NAS
#    itself doesn't need it (networking.hosts below), but browsers/runner do.
#
# Per-repo setup (Sveltia OAuth app, Actions secrets, repo creation) is
# documented in each repo — see noel-site's Readme.md.
# ---------------------------------------------------------------------------
{ config, lib, pkgs, ... }:

{
  services.forgejo = {
    enable = true;
    # sqlite is plenty for a couple of users; avoids running postgres for this
    database.type = "sqlite3";
    # ZFS so repos are snapshotted + replicated by zfs-backup-module
    stateDir = "/firstpool/family/forgejo";
    lfs.enable = true;
    settings = {
      server = {
        DOMAIN = "git.yonathan.org";
        ROOT_URL = "https://git.yonathan.org/";
        HTTP_ADDR = "127.0.0.1";
        HTTP_PORT = 3030; # 3000 is grafana
        # No git-over-ssh: the box's sshd is for admin only; git goes over HTTPS
        DISABLE_SSH = true;
        LANDING_PAGE = "explore";
      };
      service = {
        DISABLE_REGISTRATION = true; # accounts are created by the admin only
      };
      # SSO via the self-hosted Pocket ID OIDC IdP. The auth *source* itself
      # (client id/secret, discovery URL) is stored in Forgejo's DB and added
      # in the admin UI (Site Administration -> Identity & access ->
      # Authentication sources, name "pocket-id" so the callback is
      # /user/oauth2/pocket-id/callback). Only the login *behaviour* is
      # declarative here: link a first OIDC login to the existing local
      # account with the same (verified) email instead of prompting for a
      # password. New-account creation stays admin-only (registration
      # disabled above; auto-registration left at its default of off).
      oauth2_client = {
        ACCOUNT_LINKING = "auto";
        USERNAME = "preferred_username";
      };
      actions = {
        ENABLED = true;
        # where uses: actions/checkout@v4 etc. resolve from
        DEFAULT_ACTIONS_URL = "https://code.forgejo.org";
      };
      session.COOKIE_SECURE = true;
      # Sveltia CMS runs in the browser on the website origin and calls the
      # Forgejo API cross-origin; without CORS headers those calls are blocked.
      cors = {
        ENABLED = true;
        ALLOW_DOMAIN = "https://www.noelsirivansanti.com,https://noel-site.yonran.workers.dev";
        METHODS = "GET,HEAD,POST,PUT,PATCH,DELETE,OPTIONS";
        HEADERS = "Content-Type,User-Agent,Authorization";
      };
      # Sane defaults for a private family forge
      repository.DEFAULT_PRIVATE = "private";
      other.SHOW_FOOTER_VERSION = false;
    };
  };

  # The box resolves its own forge hostname locally (via Caddy on 443 with the
  # wildcard cert), so the Actions runner and local git work even though the
  # public DNS record lives in Cloudflare (managed by cloudflare-tofu).
  networking.hosts."127.0.0.1" = [ "git.yonathan.org" ];

  # Same ZFS-mount coupling as jellyfin/immich: don't start before
  # /firstpool/family is mounted, stop when it unmounts.
  systemd.services.forgejo = {
    requires = [ "firstpool-family.mount" ];
    after = [ "firstpool-family.mount" ];
    partOf = [ "firstpool-family.mount" ];
    wantedBy = [ "firstpool-family.mount" ];
    unitConfig.RequiresMountsFor = "/firstpool/family";
  };

  # Forgejo Actions runner: executes CI workflows (e.g. noel-site build +
  # `wrangler deploy` to Cloudflare Workers). Runs jobs directly on the host
  # (label native:host) instead of docker — jobs then use the hostPackages
  # below. The runner registers itself using the token in
  # /etc/secrets/forgejo-runner-token (see setup steps in the header);
  # until that file exists the runner service simply fails and retries,
  # without affecting Forgejo itself.
  services.gitea-actions-runner = {
    package = pkgs.forgejo-runner;
    instances.nas = {
      enable = true;
      name = "nas-host";
      url = "https://git.yonathan.org";
      tokenFile = "/etc/secrets/forgejo-runner-token";
      labels = [ "native:host" ];
      hostPackages = with pkgs; [
        bash
        coreutils
        curl
        gawk
        git
        gnused
        gnutar
        gzip
        nodejs_24 # astro build + npx wrangler deploy
        wget
      ];
    };
  };
  systemd.services.gitea-runner-nas = {
    requires = [ "forgejo.service" ];
    after = [ "forgejo.service" ];
    # The module defaults to DynamicUser, whose state lives under
    # /var/lib/private (0700 root). npm/node resolve that realpath and then
    # fail with EACCES executing downloaded tool binaries (e.g. esbuild)
    # from the job workspace. Use a real system user instead.
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = lib.mkForce "forgejo-runner";
      Group = lib.mkForce "forgejo-runner";
    };
  };
  users.users.forgejo-runner = {
    isSystemUser = true;
    group = "forgejo-runner";
    home = "/var/lib/gitea-runner";
  };
  users.groups.forgejo-runner = { };

  # Keep the runner's disk use bounded — it lives on the small root SSD
  # (nvme0n1p2, ~46G). Two things accumulate:
  #   - per-run `act` checkout dirs under .cache/act/<hash> (the runner never
  #     cleans these), and
  #   - saved actions/cache entries under .cache/actcache (immutable; a new one
  #     is kept whenever the workflow's cache key changes).
  # The workflow keys (npm on lockfile, astro on image content) already avoid
  # a new entry per push; this timer evicts the stale tail so it can't fill /.
  systemd.services.forgejo-runner-cache-prune = {
    description = "Prune Forgejo runner working dirs and actions cache to bound SSD use";
    serviceConfig = {
      Type = "oneshot";
      User = "forgejo-runner";
      Group = "forgejo-runner";
    };
    script = ''
      set -u
      base=/var/lib/gitea-runner/nas/.cache
      # Remove per-run act working dirs older than 2 days (regenerated per run).
      if [ -d "$base/act" ]; then
        ${pkgs.findutils}/bin/find "$base/act" -mindepth 1 -maxdepth 1 -type d \
          -mtime +2 -exec rm -rf {} + || true
      fi
      # Hard cap the actions/cache store at ~800MB; if over, clear it (the next
      # build just re-populates it). Cheap insurance against the immutable tail.
      if [ -d "$base/actcache" ]; then
        sz=$(${pkgs.coreutils}/bin/du -sm "$base/actcache" | ${pkgs.coreutils}/bin/cut -f1)
        if [ "''${sz:-0}" -gt 800 ]; then rm -rf "$base/actcache"/*; fi
      fi
    '';
  };
  # Run hourly. Not because the checkout dirs need it (they grow slowly and
  # self-limit to the 2-day window), but because the 800MB size cap is only a
  # real bound if it's checked often — the runner's cache server has no built-in
  # eviction, so a weekly check could let the store sit oversized for days on a
  # nearly-full SSD. The check is a trivial `du`, so hourly costs nothing.
  systemd.timers.forgejo-runner-cache-prune = {
    description = "Hourly size-cap check + prune of Forgejo runner cache/working dirs";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
      RandomizedDelaySec = "5m";
    };
  };
}
