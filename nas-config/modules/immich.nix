{ config, pkgs, ... }:

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

      REDIS_HOSTNAME=10.88.0.3
      DB_HOSTNAME=10.88.0.2
    '';
  };
  # Enable Podman
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  # Create bridge interface for immich
  networking.bridges.immich-br = {
    interfaces = [ ]; # Virtual bridge, no physical interfaces
  };

  networking.interfaces.immich-br = {
    ipv4.addresses = [{
      address = "10.88.0.1";
      prefixLength = 24;
    }];
  };

  # Create Podman network using the bridge interface
  systemd.services.create-immich-podman-network = {
    serviceConfig.Type = "oneshot";
    wantedBy = [ 
      "podman-immich-database.service" 
      "podman-immich-redis.service"
      "podman-immich-machine-learning.service"
      "podman-immich-server.service"
    ];
    script = ''
      ${pkgs.podman}/bin/podman network exists immich || \
      ${pkgs.podman}/bin/podman network create \
        --driver bridge \
        --opt parent=immich-br \
        --subnet 10.88.0.0/24 \
        --gateway 10.88.0.1 \
        immich
    '';
  };

  # Create immich model cache volume
  systemd.services.create-immich-model-cache = {
    serviceConfig.Type = "oneshot";
    wantedBy = [ "podman-immich-machine-learning.service" ];
    script = ''
      ${pkgs.podman}/bin/podman volume exists immich-model-cache || \
      ${pkgs.podman}/bin/podman volume create immich-model-cache
    '';
  };

  virtualisation.oci-containers.containers = {
    # Immich PostgreSQL Database
    immich-database = {
      image = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:32324a2f41df5de9efe1af166b7008c3f55646f8d0e00d9550c16c9822366b4a";
      # The EnvironmentFile is only used to 
      environmentFiles = [ "/etc/immich/.env" ];
      environment = {
        POSTGRES_PASSWORD = "\${DB_PASSWORD}";
        POSTGRES_USER = "\${DB_USERNAME}";
        POSTGRES_DB = "\${DB_DATABASE_NAME}";
        POSTGRES_INITDB_ARGS = "--data-checksums";
        DB_STORAGE_TYPE = "HDD";
      };
      volumes = [ "\${DB_DATA_LOCATION}:/var/lib/postgresql/data" ];
      extraOptions = [ 
        "--network=immich"
        "--ip=10.88.0.2"  # Static IP on bridge network
        "--shm-size=128m"
      ];
    };

    # Immich Redis Cache
    immich-redis = {
      image = "docker.io/valkey/valkey:8-bookworm@sha256:facc1d2c3462975c34e10fccb167bfa92b0e0dbd992fc282c29a61c3243afb11";
      extraOptions = [
        "--network=immich"
        "--ip=10.88.0.3"  # Static IP on bridge network
        "--health-cmd=redis-cli ping"
        "--health-interval=10s"
        "--health-timeout=5s"
        "--health-retries=3"
        "--health-on-failure=kill"
      ];
    };

    # Immich Machine Learning
    immich-machine-learning = {
      image = "ghcr.io/immich-app/immich-machine-learning:\${IMMICH_VERSION}";
      # The EnvironmentFile in Service is used for variable substitution in the unit file and is passed to podman
      environmentFiles = [ "/etc/immich/.env" ];
      environment = {
        IMMICH_HOST = "0.0.0.0";
        IMMICH_LOG_LEVEL = "debug";
      };
      volumes = [ "immich-model-cache:/cache" ];
      extraOptions = [
        "--network=immich"
        "--ip=10.88.0.4"  # Static IP on bridge network
        # HEALTHCHECK copied from https://github.com/immich-app/immich/blob/v1.137.3/machine-learning/Dockerfile
        # apparently (as of podman 5.2.3) you must provide HealthCmd even if HEALTHCHECK exists
        "--health-cmd=python3 healthcheck.py"
        "--health-interval=30s"
        "--health-timeout=20s"
        "--health-retries=5"
        "--health-start-period=60s"
        "--health-on-failure=kill"
      ];
    };

    # Immich Server
    immich-server = {
      image = "ghcr.io/immich-app/immich-server:\${IMMICH_VERSION}";
      # The EnvironmentFile in Service is used for variable substitution in the unit file and is passed to podman
      environmentFiles = [ "/etc/immich/.env" ];
      environment = {
        # IMMICH_HOST = "0.0.0.0";  # commented out from original
        IMMICH_LOG_LEVEL = "debug";
        DB_PASSWORD = "postgres";
        DB_USERNAME = "postgres";  
        DB_DATABASE_NAME = "immich";
        DB_HOSTNAME = "10.88.0.2";  # Point to database container IP
        REDIS_HOSTNAME = "10.88.0.3";  # Point to redis container IP
      };
      volumes = [
        "\${UPLOAD_LOCATION}:/data"
        "/etc/localtime:/etc/localtime:ro"
      ];
      extraOptions = [
        "--network=immich"
        "--ip=10.88.0.5"  # Static IP on bridge network
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
    };
  };

  # Service dependencies - immich-server requires redis and database
  systemd.services.podman-immich-server = {
    requires = [ "podman-immich-redis.service" "podman-immich-database.service" ];
    after = [ "podman-immich-redis.service" "podman-immich-database.service" ];
  };
}