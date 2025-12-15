# immich.nix — Option A (no pod), preserving your exact images, names, envs, health, ports
{ config, lib, pkgs, ... }:

let
  # Define variables from environment file
  UPLOAD_LOCATION = "/firstpool/family/immich/photos";
  DB_DATA_LOCATION = "/firstpool/family/immich/postgres";
  IMMICH_VERSION = "v1.144.1";
  DB_PASSWORD = "postgres";
  DB_USERNAME = "postgres";
  DB_DATABASE_NAME = "immich";
  REDIS_HOSTNAME = "immich-redis";
  DB_HOSTNAME = "immich-database";
in

{
  # Deploy environment file for Immich
  environment.etc = {
    "immich/.env".text = ''
      UPLOAD_LOCATION=${UPLOAD_LOCATION}
      DB_DATA_LOCATION=${DB_DATA_LOCATION}
      IMMICH_VERSION=${IMMICH_VERSION}
      DB_PASSWORD=${DB_PASSWORD}
      IMMICH_HOST=0.0.0.0
      IMMICH_LOG_LEVEL=debug
      DB_USERNAME=${DB_USERNAME}
      DB_DATABASE_NAME=${DB_DATABASE_NAME}
      DB_STORAGE_TYPE=HDD

      REDIS_HOSTNAME=${REDIS_HOSTNAME}
      DB_HOSTNAME=${DB_HOSTNAME}
    '';
  };
  virtualisation.podman = {
    enable = true;
    # Name-based container DNS so immich_server can reach immich_postgres / immich_redis
    defaultNetwork.settings.dns_enabled = true;
    # (left pruning/restart policies alone to match your current configs)
  };

  virtualisation.oci-containers = {
    backend = "podman";
    containers = {

      ########## Immich PostgreSQL Database ##########
      immich-database = {
        # exact image line from your .container
        image = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:32324a2f41df5de9efe1af166b7008c3f55646f8d0e00d9550c16c9822366b4a";

        environmentFiles = [ "/etc/immich/.env" ];

        # keep the same volume mapping token
        volumes = [
          "${DB_DATA_LOCATION}:/var/lib/postgresql/data"
          # postgres 14 needs to use a different pg_stats_tmp or else it will write to disk every 15s or so
          "/run/immich_pg_stat_tmp:/var/lib/postgresql/data/pg_stat_tmp"
        ];

        # shm-size in Quadlet -> Podman arg here
        extraOptions = [
          "--network=podman"
          "--shm-size=128m"
        ];

        # expose the db
        ports = [ "5432:5432/tcp" ];

        # systemd dependencies handled separately below
        dependsOn = [];
      };

      ########## Immich Redis (Valkey) ##########
      immich-redis = {
        image = "docker.io/valkey/valkey:8-bookworm@sha256:facc1d2c3462975c34e10fccb167bfa92b0e0dbd992fc282c29a61c3243afb11";

        extraOptions = [
          "--network=podman"
          # healthcheck from your Quadlet:
          "--health-cmd=redis-cli ping || exit 1"
          "--health-interval=10s"
          "--health-timeout=5s"
          "--health-retries=3"
        ];

        # systemd dependencies handled separately below
        dependsOn = [];
      };

      ########## Immich Machine Learning ##########
      immich-machine-learning = {
        image = "ghcr.io/immich-app/immich-machine-learning:${IMMICH_VERSION}";
        # The EnvironmentFile in Service is used for variable substitution in the unit file and is passed to podman
        environmentFiles = [ "/etc/immich/.env" ];
        # The EnvironmentFile in Container is passed to the container
        environment = {
          IMMICH_HOST = "0.0.0.0";
          IMMICH_LOG_LEVEL = "debug";
        };

        volumes = [
          # preserve your named volume -> container path
          "immich-model-cache:/cache"
        ];

        extraOptions = [
          "--network=podman"
          # HEALTHCHECK copied from https://github.com/immich-app/immich/blob/v1.137.3/machine-learning/Dockerfile
          # apparently (as of podman 5.2.3) you must provide HealthCmd even if HEALTHCHECK exists
          "--health-cmd=python3 healthcheck.py"
          "--health-interval=30s"
          "--health-timeout=20s"
          "--health-retries=5"
          "--health-start-period=60s"
        ];

        # systemd dependencies handled separately below
        dependsOn = [];
      };

      ########## Immich Server ##########
      immich-server = {
        image = "ghcr.io/immich-app/immich-server:${IMMICH_VERSION}";
        # The EnvironmentFile in Service is used for variable substitution in the unit file and is passed to podman
        environmentFiles = [ "/etc/immich/.env" ];
        # The EnvironmentFile in Container is passed to the container

        volumes = [
          # preserved verbatim
          "${UPLOAD_LOCATION}:/data"
          "/etc/localtime:/etc/localtime:ro"
        ];

        # Your pod exposed 2283:2283 — mirror that on the server
        ports = [ "2283:2283/tcp" "3001:2283/tcp" ];

        extraOptions = [
          "--network=podman"
          # the Dockerfile has HealthCmd but podman isn't using it
          # https://github.com/containers/podman/issues/18904
          "--health-cmd=immich-healthcheck"
          # add an action to kill the container instead of just doing nothing
          "--health-interval=30s"
          "--health-timeout=20s"
          "--health-retries=5"
          "--health-start-period=60s"
          "--health-on-failure=kill"
        ];

        # In your Quadlet, you added explicit {Requires,After} on redis/db.
        # We mirror that ordering at the systemd layer here.
        dependsOn = [ "immich-database" "immich-redis" ];
      };
    };
  };

  # Optional: create the named volume used by ML (Podman will auto-create if missing;
  # NixOS doesn't need an explicit declaration for it).
  # If you prefer host paths instead, replace "immich-model-cache:/cache" with
  # "/var/lib/immich/model-cache:/cache" and add a tmpfiles rule.

  # Convenience stack target (start/stop all together)
  systemd.targets."immich-stack" = {
    description = "Immich stack (server + db + redis + ml)";
    wantedBy = [ "multi-user.target" ];
  };

  # Configure systemd services with mount dependencies
  systemd.services.podman-immich-database = {
    requires = [ "firstpool-family.mount" "network-online.target" ];
    after = [ "firstpool-family.mount" "network-online.target" ];
    # when immich-stack is stopped or when firstpool/family is unmounted,
    # then stop immich-database
    partOf = [ "immich-stack.target" "firstpool-family.mount" ];
    # when immich-stack is started or when firstpool/family is mounted,
    # then start immich-database
    wantedBy = [ "immich-stack.target" "firstpool-family.mount" ];
    unitConfig.RequiresMountsFor = "/firstpool/family";
    # https://github.com/NixOS/nixpkgs/blob/nixos-25.05/nixos/modules/virtualisation/oci-containers.nix#L565
    
    serviceConfig.RuntimeDirectory = lib.mkForce "immich-database immich_pg_stat_tmp";
    preStart = ''
      # mkdir -p /run/immich_pg_stat_tmp
      set -eux
      chown 999:999 /run/immich_pg_stat_tmp
      # chmod 0700 /run/immich_pg_stat_tmp
    '';
  };
  
  systemd.services.podman-immich-server = {
    requires = [ "firstpool-family.mount" "network-online.target" ];
    after = [ "firstpool-family.mount" "network-online.target" ];
    partOf = [ "immich-stack.target" "firstpool-family.mount" ];
    wantedBy = [ "immich-stack.target" "firstpool-family.mount" ];
    unitConfig.RequiresMountsFor = "/firstpool/family";
  };

  systemd.services.podman-immich-machine-learning = {
    requires = [ "network-online.target" ];
    after = [ "network-online.target" ];
    wantedBy = [ "immich-stack.target" ];
    partOf = [ "immich-stack.target" ];
  };

  systemd.services.podman-immich-redis = {
    requires = [ "network-online.target" ];
    after = [ "network-online.target" ];
    wantedBy = [ "immich-stack.target" ];
    partOf = [ "immich-stack.target" ];
  };

}
