{ config, lib, pkgs, ... }:

{
  options = {
    services.zfsBackup = {
      enable = lib.mkEnableOption "ZFS backup service";
      source_pool = lib.mkOption {
        type = lib.types.str;
        default = "primarypool";
        description = "Source ZFS pool name.";
      };

      source_fs = lib.mkOption {
        type = lib.types.str;
        default = "sourcefs";
        description = "Source filesystem name.";
      };

      backup_pool = lib.mkOption {
        type = lib.types.str;
        default = "backuppool";
        description = "Backup ZFS pool name.";
      };

      backup_fs = lib.mkOption {
        type = lib.types.str;
        default = "backupfs";
        description = "Backup filesystem name.";
      };
    };
  };

  config = lib.mkIf config.services.zfsBackup.enable {
    environment.systemPackages = with pkgs; [ zfs ];

    systemd.services.zfsBackup = {
      description = "ZFS Backup Service";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.writeShellScriptBin "zfs-backup" (builtins.readFile ./zfs-backup.sh)}/bin/zfs-backup ${config.services.zfsBackup.source_pool} ${config.services.zfsBackup.source_fs} ${config.services.zfsBackup.backup_pool} ${config.services.zfsBackup.backup_fs}";
        Environment = "PATH=${lib.makeBinPath [ pkgs.zfs pkgs.coreutils pkgs.gnugrep pkgs.findutils ]}";
      };
      wantedBy = [ "multi-user.target" ];
    };

    # system.activationScripts.zfsBackup = {
    #   text = ''
    #     mkdir -p $(dirname ${config.services.zfsBackup.backupScriptPath})
    #     cp ${./zfs-backup.sh} ${config.services.zfsBackup.backupScriptPath}
    #     chmod +x ${config.services.zfsBackup.backupScriptPath}
    #   '';
    #   deps = [];
    # };

    systemd.timers.zfsBackup = {
      description = "Timer for ZFS Backup";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };
  };
}
