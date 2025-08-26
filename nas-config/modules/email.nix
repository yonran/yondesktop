{ config, lib, pkgs, ... }:

let
  cfg = config.services.alertingEmail;
in {
  options.services.alertingEmail = {
    enable = lib.mkEnableOption "Local Postfix MTA relaying to external SMTP (e.g., Gmail).";
    hostname = lib.mkOption {
      type = lib.types.str;
      default = "home.yonathan.org";
      description = "Local MTA hostname for Postfix (used in headers).";
    };
    relay = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable SMTP relay/smarthost for outbound delivery.";
      };
      host = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Relay SMTP hostname (e.g., smtp.gmail.com).";
      };
      port = lib.mkOption {
        type = lib.types.int;
        default = 587;
        description = "Relay SMTP port (typically 587).";
      };
      username = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Relay SMTP username (e.g., your Gmail address).";
      };
      envelopeFrom = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional envelope sender and From: rewrite (e.g., your Gmail address).";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.postfix = {
      enable = true;
      hostname = cfg.hostname;
      config =
        let
          base = {
            inet_interfaces = "loopback-only"; # local-only SMTP submission
            mydestination = "";               # no domain-based local delivery
            local_header_rewrite_clients = "permit_mynetworks";
          };
          relay = if cfg.relay.enable then {
            relayhost = "[${cfg.relay.host}]:${toString cfg.relay.port}";
            smtp_sasl_auth_enable = "yes";
            smtp_sasl_security_options = "noanonymous";
            smtp_sasl_password_maps = "texthash:/etc/postfix/sasl_passwd";
            smtp_tls_security_level = "encrypt"; # require STARTTLS to relay
            smtp_tls_loglevel = "1";
          } else {
            # direct delivery if desired (not typical on residential ISPs)
            smtp_tls_security_level = "may";
          };
          rewrite = if (cfg.relay.enable && cfg.relay.envelopeFrom != null) then {
            sender_canonical_classes = "envelope_sender";
            sender_canonical_maps = "texthash:/etc/postfix/sender_canonical";
            smtp_generic_maps = "texthash:/etc/postfix/generic";
          } else {};
        in base // relay // rewrite;
    };
    services.postfix.mapFiles = lib.mkIf (cfg.relay.enable && cfg.relay.envelopeFrom != null) {
      sender_canonical = pkgs.writeText "sender_canonical" ''
        @${cfg.hostname} ${cfg.relay.envelopeFrom}
        @localhost ${cfg.relay.envelopeFrom}
      '';
      generic = pkgs.writeText "generic" ''
        @${cfg.hostname} ${cfg.relay.envelopeFrom}
        @localhost ${cfg.relay.envelopeFrom}
      '';
    };

    # Helper README for credentials file
    # Note: create /etc/postfix/sasl_passwd manually on the host (0600 root) and reload postfix.
  };
}
