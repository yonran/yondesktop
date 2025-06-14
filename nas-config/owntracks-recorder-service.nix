{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.owntracks-recorder;
  # owntracks-recorder-package = pkgs.owntracks-recorder;
  owntracks-recorder-package = pkgs.callPackage ./owntracks-recorder.nix {};
in {
  options.services.owntracks-recorder = {
    enable = mkEnableOption "owntracks-recorder service";
    metricsPort = mkOption {
      type = types.int;
      default = 8200;
      description = "Port to listen on";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.owntracks-recorder = {
      description = "owntracks-recorder Service";
      wantedBy = [ "multi-user.target" ];
      wants = [ "mosquitto.service" ];
      after = [ "network.target" "mosquitto.service" ];
      serviceConfig = {
        ExecStart = "${owntracks-recorder-package}/bin/ot-recorder owntracks/#  ";
        User = "owntracks-recorder";
        Group = "owntracks-recorder";
        # all the config is in /etc/default/ot-recorder
        # Environment = {
        #   "OTR_PORT" = "${toString cfg.metricsPort}";
        # };
      };
    };

    users.users.owntracks-recorder = {
      isSystemUser = true;
      group = "owntracks-recorder";
    };

    users.groups.owntracks-recorder = {};
  };
}

