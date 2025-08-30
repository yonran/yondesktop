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

    # Systemd service to backup owntracks data to ZFS pool
    systemd.services.owntracks-backup = {
      description = "Backup owntracks data to ZFS pool";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = pkgs.writeShellScript "owntracks-backup" ''
          set -euo pipefail
          
          # Create backup directory if it doesn't exist
          mkdir -p /firstpool/family/owntracks/recorder/store
          
          # Sync data to ZFS backup (preserve timestamps, permissions, no --delete)
          ${pkgs.rsync}/bin/rsync -av \
            /var/spool/owntracks/recorder/store/ \
            /firstpool/family/owntracks/recorder/store/
          
          # # Clean up old files from root fs (keep last 24 hours)
          # ${pkgs.findutils}/bin/find /var/spool/owntracks/recorder/store \
          #   -type f -mtime +1 -name "*.rec" -delete
          
          echo "$(date): Owntracks backup completed"
        '';
      };
      unitConfig.RequiresMountsFor = "/firstpool/family";
    };

    # Timer to run backup every day
    systemd.timers.owntracks-backup = {
      description = "Timer for owntracks backup";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 00:00:00 America/Los_Angeles";  # every day around 
        Persistent = true;
        RandomizedDelaySec = "120";  # Random delay up to 2 minutes
      };
    };
  };
}

