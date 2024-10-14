{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.sb-exporter;
  sb-exporter-package = pkgs.callPackage ./sb-exporter.nix {};
in {
  options.services.sb-exporter = {
    enable = mkEnableOption "sb-exporter service";
    secretFile = mkOption {
      type = types.str;
      description = "Path to the file containing the secret";
    };
    metricsPort = mkOption {
      type = types.int;
      default = 8200;
      description = "Port to listen on";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.sb-exporter = {
      description = "sb-exporter Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        ExecStart = "${sb-exporter-package}/bin/main.py";
        User = "sb-exporter";
        Group = "sb-exporter";
        EnvironmentFile = cfg.secretFile;
        # Environment = {
        #   "METRICS_PORT" = "${toString cfg.metricsPort}";
        # };
      };
    };

    users.users.sb-exporter = {
      isSystemUser = true;
      group = "sb-exporter";
    };

    users.groups.sb-exporter = {};
  };
}

