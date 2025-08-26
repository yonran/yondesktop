{ config, lib, pkgs, ... }:

{
  imports = [
    ./sb-exporter-service.nix
  ];
  options = {
    services.home-monitoring = {
      enable = lib.mkEnableOption "grafana and prometheus for cable modem monitoring";
      alertEmail = {
        toAddress = lib.mkOption {
          type = lib.types.str;
          default = "yonathan@gmail.com";
          description = "Alert e-mail recipient.";
        };
        fromAddress = lib.mkOption {
          type = lib.types.str;
          default = "yonathan@gmail.com";
          description = "Alert e-mail sender address.";
        };
        smtpSmarthost = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1:25";
          description = "SMTP smarthost Alertmanager connects to (usually local Postfix).";
        };
      };
      diskFreeBytesThreshold = lib.mkOption {
        type = lib.types.int;
        default = 1073741824; # 1 GiB
        description = "Disk free threshold in bytes to trigger alert.";
      };
    };
  };

  config = lib.mkIf config.services.home-monitoring.enable {
    environment.systemPackages = with pkgs; [ zfs ];

    # Enable Prometheus
    services.prometheus = {
      enable = true;
      port = 9090;
      exporters = {
        node = {
          enable = true;
          enabledCollectors = [ "systemd" ];
          port = 9100;
        };
      };
      scrapeConfigs = [
        {
          job_name = "node";
          static_configs = [{
            targets = [ "localhost:${toString config.services.prometheus.exporters.node.port}" ];
          }];
        }
        {
          job_name = "blackbox";
          metrics_path = "/probe";
          params = {
            module = [ "icmp" ];
          };
          static_configs = [{
            targets = [
              "google.com"
              "192.168.1.1"  # Assumes this is your router's IP. Adjust if different.
              "192.168.100.1"  # cable modem
              # see Netgear R6400v2 -> Advanced tab -> ADVANCED Home -> Internet Port
              "75.75.75.75"  # Comcast DNS
              "75.75.76.76"  # Comcast DNS
            ];
          }];
          relabel_configs = [{
            source_labels = [ "__address__" ];
            target_label = "__param_target";
          }
          {
            source_labels = [ "__param_target" ];
            target_label = "instance";
          }
          {
            target_label = "__address__";
            replacement = "localhost:9115";  # Blackbox exporter.
          }];
        }
        {
          job_name = "sb-exporter";
          metrics_path = "/";
          static_configs = [{
            targets = [ "localhost:${toString config.services.sb-exporter.metricsPort}" ];
          }];
        }
      ];
      # Point Prometheus at Alertmanager
      alertmanagers = [
        { static_configs = [ { targets = [ "127.0.0.1:9093" ]; } ]; }
      ];
      # Storage alert: any non-ephemeral FS below threshold
      ruleFiles = [
        (pkgs.writeText "nas-storage-alerts.yml" ''
          groups:
          - name: storage
            rules:
            - alert: DiskFreeBelowThreshold
              expr: min by (instance, mountpoint, device) (
                      node_filesystem_avail_bytes{
                        fstype!~"tmpfs|devtmpfs|overlay|squashfs|ramfs|autofs|proc|sysfs|cgroup.*|bpf|nsfs|tracefs",
                        mountpoint!~"/nix/store|/run($|/.*)|/boot"
                      }
                    ) < ${toString config.services.home-monitoring.diskFreeBytesThreshold}
              for: 5m
              labels:
                severity: critical
              annotations:
                summary: "Low disk space on {{ $labels.instance }} {{ $labels.mountpoint }}"
                description: "Available space is below ${toString config.services.home-monitoring.diskFreeBytesThreshold} bytes on {{ $labels.device }} mounted at {{ $labels.mountpoint }} ({{ $value | humanize1024 }} left)."
        '')
      ];
    };

    # Enable and configure Blackbox exporter
    services.prometheus.exporters.blackbox = {
      enable = true;
      configFile = pkgs.writeText "blackbox.yml" ''
        modules:
          icmp:
            prober: icmp
            timeout: 5s
            icmp:
              preferred_ip_protocol: ip4
      '';
    };
    services.sb-exporter.enable = true;
    services.sb-exporter.secretFile = "/etc/sb-exporter.env";

    # Enable Grafana
    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_addr = "0.0.0.0";
          http_port = 3000;
        };
      };
    };

    # Alertmanager for e-mailing Prometheus alerts
    services.prometheus.alertmanager = {
      enable = true;
      listenAddress = ""; # Empty string will listen on all interfaces
      port = 9093;
      configuration = {
        global = {
          smtp_from = config.services.home-monitoring.alertEmail.fromAddress;
          smtp_smarthost = config.services.home-monitoring.alertEmail.smtpSmarthost;
        };
        route = {
          group_by = [ "alertname" "instance" ];
          receiver = "email";
        };
        receivers = [
          {
            name = "email";
            email_configs = [
              {
                to = config.services.home-monitoring.alertEmail.toAddress;
                send_resolved = true;
              }
            ];
          }
        ];
      };
    };

    # ZFS Event Daemon e-mail notifications (25.05): settings only
    services.zfs.zed.settings = {
      ZED_EMAIL_ADDR = config.services.home-monitoring.alertEmail.toAddress;
      ZED_EMAIL_PROG = "/run/wrappers/bin/sendmail";
    };

    # Open necessary ports in the firewall
    networking.firewall.allowedTCPPorts = [
      config.services.grafana.settings.server.http_port
      config.services.prometheus.port
      config.services.prometheus.exporters.node.port
      config.services.prometheus.alertmanager.port
      9115  # Blackbox exporter
      config.services.sb-exporter.metricsPort
    ];
  };
}
