{ config, lib, pkgs, ... }:

{
  imports = [
    ./sb-exporter-service.nix
  ];
  options = {
    services.home-monitoring = {
      enable = lib.mkEnableOption "grafana and prometheus for cable modem monitoring";
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

    # Open necessary ports in the firewall
    networking.firewall.allowedTCPPorts = [
      config.services.grafana.settings.server.http_port
      config.services.prometheus.port
      config.services.prometheus.exporters.node.port
      9115  # Blackbox exporter
      config.services.sb-exporter.metricsPort
    ];
  };
}
