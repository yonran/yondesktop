# immich.nix — Option A (no pod), preserving your exact images, names, envs, health, ports
{ config, lib, pkgs, ... }:

let
  # Define variables from environment file
  UPLOAD_LOCATION = "/firstpool/family/immich/photos";
  DB_DATA_LOCATION = "/firstpool/family/immich/postgres";
  IMMICH_VERSION = "v1.137.3";
in

{
  # Deploy environment file for Immich
  environment.etc = {
    "immich/.env".text = ''
      UPLOAD_LOCATION=/firstpool/family/immich/photos
      DB_DATA_LOCATION=/firstpool/family/immich/postgres
      IMMICH_VERSION=v1.137.3
      DB_PASSWORD=postgres
      IMMICH_HOST=0.0.0.0
      IMMICH_LOG_LEVEL=debug
      DB_USERNAME=postgres
      DB_DATABASE_NAME=immich
      DB_STORAGE_TYPE=HDD

      REDIS_HOSTNAME=immich_redis
      DB_HOSTNAME=immich_postgres
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
      immich_postgres = {
        # exact image line from your .container
        image = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:32324a2f41df5de9efe1af166b7008c3f55646f8d0e00d9550c16c9822366b4a";

        environmentFiles = [ "/etc/immich/.env" ];
        environment = {
          POSTGRES_PASSWORD = "postgres";
          POSTGRES_USER = "postgres";
          POSTGRES_DB = "immich";
          POSTGRES_INITDB_ARGS = "--data-checksums";
          DB_STORAGE_TYPE = "HDD";
        };

        # keep the same volume mapping token
        volumes = [
          "${DB_DATA_LOCATION}:/var/lib/postgresql/data"
        ];

        # shm-size in Quadlet -> Podman arg here
        extraOptions = [
          "--network=podman"
          "--shm-size=128m"
        ];

        # No Restart= in your Quadlet -> leave defaults here too
      };

      ########## Immich Redis (Valkey) ##########
      immich_redis = {
        image = "docker.io/valkey/valkey:8-bookworm@sha256:facc1d2c3462975c34e10fccb167bfa92b0e0dbd992fc282c29a61c3243afb11";

        extraOptions = [
          "--network=podman"
          # healthcheck from your Quadlet:
          "--health-cmd=redis-cli ping || exit 1"
          "--health-interval=10s"
          "--health-timeout=5s"
          "--health-retries=3"
        ];

        # no restart policy set in your Quadlet -> unchanged
      };

      ########## Immich Machine Learning ##########
      immich_machine_learning = {
        image = "ghcr.io/immich-app/immich-machine-learning:${IMMICH_VERSION}";
        environmentFiles = [ "/etc/immich/.env" ];
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
          # healthcheck copied from your Quadlet
          "--health-cmd=python3 healthcheck.py"
          "--health-interval=30s"
          "--health-timeout=20s"
          "--health-retries=5"
          "--health-start-period=60s"
        ];
      };

      ########## Immich Server ##########
      immich_server = {
        image = "ghcr.io/immich-app/immich-server:${IMMICH_VERSION}";
        environmentFiles = [ "/etc/immich/.env" ];
        environment = {
          IMMICH_HOST = "0.0.0.0";
          IMMICH_LOG_LEVEL = "debug";

          # keep exactly what you had in the Quadlet
          DB_PASSWORD = "postgres";
          DB_USERNAME = "postgres";
          DB_DATABASE_NAME = "immich";
          # Hostnames come from /etc/immich/.env if you set them there.
          # On this no-pod setup with DNS, use:
          #   DB_HOSTNAME=immich_postgres
          #   REDIS_HOSTNAME=immich_redis
          # but I'm not forcing them here to honor your "same variables" request.
        };

        volumes = [
          # preserved verbatim
          "${UPLOAD_LOCATION}:/data"
          "/etc/localtime:/etc/localtime:ro"
        ];

        # Your pod exposed 2283:2283 — mirror that on the server
        ports = [ "2283:2283/tcp" "3001:2283/tcp" ];

        extraOptions = [
          "--network=podman"
          # (no HealthOnFailure override since your server Quadlet didn't include one)
        ];

        # In your Quadlet, you added explicit {Requires,After} on redis/db.
        # We mirror that ordering at the systemd layer here.
        dependsOn = [ "immich_postgres" "immich_redis" ];
      };
    };
  };

  # Optional: create the named volume used by ML (Podman will auto-create if missing;
  # NixOS doesn't need an explicit declaration for it).
  # If you prefer host paths instead, replace "immich-model-cache:/cache" with
  # "/var/lib/immich/model-cache:/cache" and add a tmpfiles rule.

  # If you want a convenience stack target (start/stop all together), uncomment:
  systemd.targets."immich-stack" = {
    description = "Immich stack (server + db + redis + ml)";
    wantedBy = [ "multi-user.target" ];
  };
  systemd.services.podman-immich_postgres.partOf = [ "immich-stack.target" ];
  systemd.services.podman-immich_redis.partOf = [ "immich-stack.target" ];
  systemd.services.podman-immich_machine_learning.partOf = [ "immich-stack.target" ];
  systemd.services.podman-immich_server.partOf = [ "immich-stack.target" ];
}
