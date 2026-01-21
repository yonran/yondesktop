# zfs-unlock-web.nix - NixOS module for ZFS unlock web GUI
#
# Provides a socket-activated Flask web application for unlocking ZFS encrypted
# datasets. Authentication is handled by Caddy (Google OIDC), and the service
# runs as an unprivileged user.
#
# Required one-time setup (run as root after pool import):
#   zfs allow -u zfs-unlock load-key,mount firstpool/family
{ config, lib, pkgs, ... }:

let
  cfg = config.services.zfs-unlock-web;

  # Python environment with Flask and the app
  pythonEnv = pkgs.python3.withPackages (ps: [
    ps.flask
  ]);

  # Build the Python application
  zfs-unlock-web = pkgs.python3Packages.buildPythonApplication {
    pname = "zfs-unlock-web";
    version = "0.1.0";
    pyproject = true;

    src = ../zfs-unlock-web;

    build-system = [ pkgs.python3Packages.setuptools ];

    dependencies = [ pkgs.python3Packages.flask ];

    # No tests to run
    doCheck = false;
  };

in {
  options.services.zfs-unlock-web = {
    enable = lib.mkEnableOption "ZFS unlock web GUI";

    dataset = lib.mkOption {
      type = lib.types.str;
      default = "firstpool/family";
      description = "The ZFS dataset to unlock";
    };

    mountUnit = lib.mkOption {
      type = lib.types.str;
      default = "firstpool-family.mount";
      description = "The systemd mount unit to start after loading the key";
    };

    socketPath = lib.mkOption {
      type = lib.types.str;
      default = "/run/zfs-unlock-web.sock";
      description = "Path to the Unix socket";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "zfs-unlock";
      description = "User to run the service as";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "zfs-unlock";
      description = "Group for the service and socket";
    };

    idleTimeout = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = "Seconds of idle time before uwsgi shuts down";
    };
  };

  config = lib.mkIf cfg.enable {
    # Create the system user
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      description = "ZFS unlock web service user";
    };

    users.groups.${cfg.group} = {};

    # Sudoers rules for zfs mount and starting dependent services
    # zfs load-key uses 'zfs allow' delegation - see module header comment
    security.sudo.extraRules = [
      {
        users = [ cfg.user ];
        commands = [
          {
            command = "/run/current-system/sw/bin/zfs mount ${cfg.dataset}";
            options = [ "NOPASSWD" ];
          }
          {
            command = "/run/current-system/sw/bin/systemctl start immich-stack.target";
            options = [ "NOPASSWD" ];
          }
          {
            command = "/run/current-system/sw/bin/systemctl start jellyfin.service";
            options = [ "NOPASSWD" ];
          }
          {
            command = "/run/current-system/sw/bin/systemctl start samba-smbd.service";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    # Socket unit - systemd manages this and activates the service on connection
    systemd.sockets.zfs-unlock-web = {
      description = "ZFS Unlock Web GUI Socket";
      wantedBy = [ "sockets.target" ];

      socketConfig = {
        ListenStream = cfg.socketPath;
        SocketUser = cfg.user;
        SocketGroup = cfg.group;
        SocketMode = "0660";
      };
    };

    # Service unit - runs uwsgi with socket activation and idle shutdown
    systemd.services.zfs-unlock-web = {
      description = "ZFS Unlock Web GUI Service";

      # Only start via socket activation
      requires = [ "zfs-unlock-web.socket" ];
      after = [ "zfs-unlock-web.socket" ];

      path = [ "/run/wrappers" pkgs.zfs pkgs.systemd ];

      environment = {
        # Set Flask to production mode
        FLASK_ENV = "production";
        # Python path for uwsgi to find Flask and the app
        PYTHONPATH = "${pythonEnv}/${pkgs.python3.sitePackages}:${zfs-unlock-web}/${pkgs.python3.sitePackages}";
      };

      serviceConfig = {
        # uWSGI automatically sends READY=1 to systemd when it's ready
        Type = "notify";
        # Master process (not main PID) sends the notification
        NotifyAccess = "all";
        User = cfg.user;
        Group = cfg.group;

        # uwsgi with socket activation:
        # - --http-socket fd://3: accept HTTP connections from systemd socket (fd 3)
        # - --wsgi-file: point to the Flask application
        # - --callable application: use the 'application' WSGI callable
        # - --idle: shutdown after N seconds of no requests
        # - --die-on-idle: exit cleanly when idle timeout is reached
        # - --need-app: fail if the app can't be loaded
        # - --master: run a master process for worker management
        # - --processes 1: single worker (sufficient for low-traffic unlock service)
        # - --enable-threads: allow threads for Flask
        ExecStart = ''
          ${pkgs.uwsgi.override { plugins = [ "python3" ]; }}/bin/uwsgi \
            --http-socket fd://3 \
            --plugin python3 \
            --wsgi-file ${zfs-unlock-web}/${pkgs.python3.sitePackages}/zfs_unlock_web/__init__.py \
            --callable application \
            --idle ${toString cfg.idleTimeout} \
            --die-on-idle \
            --need-app \
            --master \
            --processes 1 \
            --enable-threads
        '';

        # Security hardening largely disabled for mount operations
        # Many Protect* options create private mount namespaces, which
        # would make zfs mount only visible within the service's namespace.
        # We need mounts to be visible system-wide.
        ProtectSystem = false;
        ProtectHome = false;
        PrivateTmp = false;
        ProtectControlGroups = false;
        ProtectKernelLogs = false;
        ProtectKernelModules = false;
        ProtectKernelTunables = false;
        # NoNewPrivileges/RestrictSUIDSGID must be false to allow sudo
        NoNewPrivileges = false;
        RestrictSUIDSGID = false;
        RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];

        # Allow reading /proc for subprocess calls
        ProcSubset = "all";

        # Restart on failure (but not on idle shutdown)
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
