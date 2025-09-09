# This is the configuration.nix for a Macbook Pro
# that I have converted to my personal server.
# To apply it, run `sudo nixos-rebuild switch`.

# This file (and hardware-configuration.nix) was originally generated
# by `nixos-generate-config` but I am customizing it 

# rsync --rsync-path="sudo rsync" ~/Documents/nixdesktop/nas-config/configuration.nix yonran@yonnas.local.:/etc/nixos/configuration.nix && ssh yonran@yonnas.local. -- sudo nixos-rebuild switch

# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./zfs-backup-module.nix
      ./home-monitoring.nix
      ./modules/email.nix
      ./owntracks-recorder-service.nix
      ./modules/immich.nix
      ./modules/monitoring-scripts.nix
    ];
  # enable zfs-backup-module
  services.zfsBackup = {
    enable = true;
    source_pool = "firstpool";
    source_fs = "family";
    backup_pool = "backuppool";
    backup_fs = "family_backup";
  };
  # enable home-monitoring
  services.home-monitoring = {
    enable = true;
  };
  # email relay MTA (local Postfix only; used by Alertmanager/ZED)
  services.alertingEmail = {
    enable = true;
    hostname = "home.yonathan.org";
    relay = {
      enable = true;
      host = "smtp.gmail.com";
      port = 587;
      username = "yonathan@gmail.com";
      envelopeFrom = "yonathan@gmail.com";
    };
  };

  # alert email settings for monitoring
  services.home-monitoring.alertEmail = {
    toAddress = "yonathan@gmail.com";
    fromAddress = "yonathan@gmail.com";
    smtpSmarthost = "127.0.0.1:25"; # local Postfix
  };
  # enable mqtt server (needed for owntracks-recorder)
  services.mosquitto = {
    enable = true;
    listeners = [
      {
        port = 1883;
        address = "localhost";  # This enables both ::1 and 127.0.0.1
        settings = {
          allow_anonymous = true;
        };
      }
      {
        port = 1883;
        address = "192.168.29.3"; # wireguard
        settings = {
          allow_anonymous = true;
        };
      }
    ];
  };


  boot.supportedFilesystems = [ "zfs" ];
  # ZFS is not needed during early boot and this flag is recommended to be off
  # (https://openzfs.github.io/openzfs-docs/Getting%20Started/NixOS/)
  boot.zfs.forceImportRoot = false;
  # hostId is written to /etc/hostid.
  # It should be unique among your computers so that zfs import gives an error
  # when you zfs import a zpool to another computer without exporting it first.
  networking.hostId = "2220fa03";
  networking.firewall = {
    # enable wireguard https://nixos.wiki/wiki/WireGuard
    # also open UDP/443 for HTTP/3 (QUIC)
    allowedUDPPorts = [ 51820 443 ];
    # enable iperf
    allowedTCPPorts = [ 5201 80 443 ];
  };
  networking.firewall.interfaces.wg0 = {
    allowedTCPPorts = [
      1883 # mosquitto mqtt
      8083 # owntracks-recorder ot-recorder
    ];
  };

  # enable wireguard https://nixos.wiki/wiki/WireGuard
  networking.wireguard.interfaces = {
    # "wg0" is the network interface name. You can name the interface arbitrarily.
    wg0 = {
      # Determines the IP address and subnet of the server's end of the tunnel interface.
      ips = [ "192.168.29.3/24" ];

      # The port that WireGuard listens to. Must be accessible by the client.
      listenPort = 51820;

      # Set MTU to 1280 to avoid PMTU blackhole issues. Path MTU testing shows
      # 1368 bytes max (AT&T SF to Comcast Seattle), but 1280 provides safe margin
      # for WireGuard overhead and is the IPv6 minimum MTU (RFC 8200).
      mtu = 1280;

      # This allows the wireguard server to route your traffic to the internet and hence be like a VPN
      # For this to work you have to set the dnsserver IP of your router (or dnsserver of choice) in your clients
      # postSetup = ''
      #   ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s 10.100.0.0/24 -o eth0 -j MASQUERADE
      # '';

      # This undoes the above command
      # postShutdown = ''
      #   ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s 10.100.0.0/24 -o eth0 -j MASQUERADE
      # '';

      # Path to the private key file.
      #
      # Note: The private key can also be included inline via the privateKey option,
      # but this makes the private key world-readable; thus, using privateKeyFile is
      # recommended.
      privateKeyFile = "/private/wireguard_key";
      generatePrivateKeyFile = true;

      peers = [
        # List of allowed peers.
        {
          # 2023 work laptop WireGuard.app
          publicKey = "8fv8YGguu/6DUAD/FHNDZJYF1UfphJAJGfbreDS8S0I=";
          # List of IPs assigned to this peer within the tunnel subnet. Used to configure routing.
          allowedIPs = [ "192.168.29.4/32" ];
        }
        { # pixel 6 android
          publicKey = "4boY8Zz2DokrHk85BhuUhfIgFIeanUp8HCY9hlyG6nw=";
          # List of IPs assigned to this peer within the tunnel subnet. Used to configure routing.
          allowedIPs = [ "192.168.29.5/32" ];
        }
        { # N iPhone
          publicKey = "O703HWP3+ZYx4Imhv4Nfbqg6Y8DJ8/JNOISmMPYDMDo=";
          # List of IPs assigned to this peer within the tunnel subnet. Used to configure routing.
          allowedIPs = [ "192.168.29.6/32" ];
        }
        { # N laptop
          publicKey = "jW3RCtvVvbYYvKVAoWIATPKURTL5DnUCMpyLo+Lar2s=";
          # List of IPs assigned to this peer within the tunnel subnet. Used to configure routing.
          allowedIPs = [ "192.168.29.7/32" ];
        }
      ];
    };
  };

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  fileSystems."/stuff" = { device = "/dev/disk/by-uuid/508E-0B16"; options = ["noatime" "nofail"]; };
  fileSystems."/Primary" = { device = "/dev/disk/by-uuid/0AB088281A56593B"; options = ["noatime" "nofail"]; };

  networking.hostName = "yonnas"; # Define your hostname. 
 
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    # `nixos-generate-config` discovered config.boot.kernelPackages.broadcom_sta,
    # but it is not free so `nix-rebuild` fails until we add this allowUnfree.
    "broadcom-sta"
  ];
  # Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  # i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkb.options in tty.
  # };

  # Enable the X11 windowing system.
  # services.xserver.enable = true;


  

  # Configure keymap in X11
  # services.xserver.xkb.layout = "us";
  # services.xserver.xkb.options = "eurosign:e,caps:escape";

  services.avahi.enable = true;
  services.avahi.publish = {
    enable = true;
    addresses = true; # publish the IP address of this machine
    workstation = true; # publish the machine as a workstatino, which includes the hostname
  };

  # enable samba and samba-wsdd https://nixos.wiki/wiki/Samba
  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        "workgroup" = "WORKGROUP";
        "server string" = "smbnix";
        "netbios name" = "smbnix";
        "security" = "user";
        #"use sendfile" = "yes";
        #"max protocol" = "smb2";
        # note: localhost is the ipv6 localhost ::1
        "hosts allow" = "192.168.1. 127.0.0.1 localhost 192.168.29.";
        "hosts deny" = "0.0.0.0/0";
        "guest account" = "nobody";
        "map to guest" = "bad user";
      };
      "public" = {
        "path" = "/firstpool/family/media";
        "browseable" = "yes";
        "read only" = "no";
        "guest ok" = "yes";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force user" = "yonran";
        "force group" = "users";
        # Recycle bin for safe deletes
        "vfs objects" = "recycle";
        "recycle:repository" = ".recycle";
        "recycle:keeptree" = "yes";
        "recycle:versions" = "yes";
        "recycle:touch" = "yes";
        "recycle:touch_mtime" = "yes";
        "recycle:exclude" = "*.tmp,*.temp,~$*";
        "recycle:exclude_dir" = ".recycle";
      };
      "private" = {
        # smbpasswd -a username
        "path" = "/firstpool/family/privateshare";
        "browseable" = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force user" = "yonran";
        "force group" = "users";
        # Recycle bin for safe deletes
        "vfs objects" = "recycle";
        "recycle:repository" = ".recycle";
        "recycle:keeptree" = "yes";
        "recycle:versions" = "yes";
        "recycle:touch" = "yes";
        "recycle:touch_mtime" = "no";
        "recycle:exclude" = "*.tmp,*.temp,~$*";
        "recycle:exclude_dir" = ".recycle";
      };
      # Additional user shares within /firstpool/family
      "yonran" = {
        "path" = "/firstpool/family/yonran";
        "browseable" = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0755";
        "directory mask" = "0755";
        "force user" = "yonran";
        "force group" = "users";
        "valid users" = "yonran";
        # Recycle bin for safe deletes
        "vfs objects" = "recycle";
        "recycle:repository" = ".recycle";
        "recycle:keeptree" = "yes";
        "recycle:versions" = "yes";
        "recycle:touch" = "yes";
        "recycle:touch_mtime" = "no";
        "recycle:exclude" = "*.tmp,*.temp,~$*";
        "recycle:exclude_dir" = ".recycle";
      };
      "nosiri" = {
        "path" = "/firstpool/family/nosiri";
        "browseable" = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0755";
        "directory mask" = "0755";
        "force group" = "users";
        "valid users" = "nosiri";
        # Recycle bin for safe deletes
        "vfs objects" = "recycle";
        "recycle:repository" = ".recycle";
        "recycle:keeptree" = "yes";
        "recycle:versions" = "yes";
        "recycle:touch" = "yes";
        "recycle:touch_mtime" = "no";
        "recycle:exclude" = "*.tmp,*.temp,~$*";
        "recycle:exclude_dir" = ".recycle";
      };
      "yonran+nosiri" = {
        "path" = "/firstpool/family/yonran+nosiri";
        "browseable" = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0755";
        "directory mask" = "0755";
        "force user" = "yonran";
        "force group" = "users";
        "valid users" = "yonran nosiri";
        # Recycle bin for safe deletes
        "vfs objects" = "recycle";
        "recycle:repository" = ".recycle";
        "recycle:keeptree" = "yes";
        "recycle:versions" = "yes";
        "recycle:touch" = "yes";
        "recycle:touch_mtime" = "no";
        "recycle:exclude" = "*.tmp,*.temp,~$*";
        "recycle:exclude_dir" = ".recycle";
      };
    };
  };
  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };

  # Jellyfin media server
  # - Listens on 8096 (HTTP) and optionally 8920 (HTTPS)
  # - Expose on LAN by opening firewall
  # - Enable VAAPI hardware acceleration by granting access to render/video
  services.jellyfin = {
    enable = true;
    openFirewall = true; # open 8096/8920
  };

  # Constrain Jellyfin to a single read-only media path using systemd sandboxing.
  # Expose your desired media directory at /srv/jellyfin-media inside the service
  # and hide the rest of the storage roots.
  systemd.tmpfiles.rules = [
    # Ensure Jellyfin writable paths exist before namespacing
    "d /var/lib/jellyfin 0750 jellyfin jellyfin -"
    "d /var/cache/jellyfin 0750 jellyfin jellyfin -"
    "d /var/log/jellyfin 0750 jellyfin jellyfin -"
    # Bind target for media inside the sandbox
    "d /srv/jellyfin-media 0755 jellyfin jellyfin -"
  ];
  systemd.services.jellyfin = {
    after = [ "local-fs.target" ];
    serviceConfig = {
      # File-system lockdown: only write to state/cache/logs; media is read-only
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      ProtectControlGroups = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      RestrictSUIDSGID = true;
      # Avoid JIT/CLR issues during startup
      # LockPersonality and MemoryDenyWriteExecute disabled for .NET runtime
      CapabilityBoundingSet = "";
      AmbientCapabilities = "";
      RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
      ReadWritePaths = [ 
        "/var/lib/jellyfin"
        "/var/cache/jellyfin"
        "/var/log/jellyfin"
      ];
      # Create standard state/cache/log directories with correct ownership
      StateDirectory = "jellyfin";
      CacheDirectory = "jellyfin";
      LogsDirectory = "jellyfin";
      # Bind the allowed media directory into a dedicated path inside the unit's namespace (read-only)
      BindReadOnlyPaths = [ 
        "/firstpool/family/media:/firstpool/family/media"
      ];
      TemporaryFileSystem = [
        # “This is useful to hide files or directories not relevant to the processes invoked by the unit,
        # while necessary files or directories can be still accessed
        # by combining with BindPaths= or BindReadOnlyPaths=:”
        # https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html#TemporaryFileSystem=
        "/firstpool"
      ];
      # Hide common storage roots to reduce what the service can see
      InaccessiblePaths = [ 
        "/home"
        "/root"
        "/mnt"
        "-/Primary"
        "-/Stuff"
      ];
      # Restrict device access: allow only GPU render/card for VAAPI
      DevicePolicy = "closed";
      DeviceAllow = [
        # Allow all DRM (Direct Rendering Manager) character devices (e.g., /dev/dri/card*, /dev/dri/renderD*)
        # DRM char devices use major 226; wildcard minor to cover cardN and renderDNN.
        "char-226:* rw"
      ];
      # Keep access to standard pseudo devices granted by DevicePolicy=closed
      # (/dev/null, /dev/zero, /dev/random, /dev/urandom, /dev/tty, etc.).
    };
  };

  # Hardware acceleration (VAAPI) for Jellyfin transcoding
  # Newer NixOS uses hardware.graphics (opengl options are deprecated)
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver # Intel iHD (Gen9+)
      vaapiIntel         # Intel i965 (older gens)
      vaapiVdpau
      libvdpau-va-gl
    ];
  };
  users.users.jellyfin.extraGroups = [ "video" "render" ];


  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Caddy reverse proxy for Immich over HTTPS with rate limiting plugin and HSTS
  services.caddy = {
    enable = true;
    email = "yonathan@gmail.com"; # ACME contact
    # Build Caddy with the rate_limit plugin
    package = pkgs.caddy.withPlugins {
      plugins = [
        "github.com/mholt/caddy-ratelimit@v0.1.1-0.20250318145942-a8e9f68d7bed"
        "github.com/caddy-dns/cloudflare@v0.2.2-0.20250724223520-f589a18c0f5d"
        "github.com/greenpau/caddy-security@v1.1.31"
      ];
      hash = "sha256-n9tslwOhZTjP1OWPMt7rZJJ/aojHQmUNUZVlZopEvNk=";
    };
    # Global Caddyfile (must be first). Use globalConfig to emit it at top.
    globalConfig = ''
      debug
      # Ensure plugin directives order well
      order authenticate before respond
      order authorize before reverse_proxy

      # Configure caddy-security app: Google OIDC portal and policy
      security {
        # Define Google OAuth2 IdP using shortcut (client_id client_secret)
        oauth identity provider google {file.{$GOOGLE_CLIENT_ID_FILE}} {file.{$GOOGLE_CLIENT_SECRET_FILE}}

        # Authentication portal issues/validates tokens; requires a signing key
        authentication portal myportal {
          # Provide a signing key; read it from a credential file
          crypto key sign-verify {file.{$AUTH_SIGN_KEY_FILE}}
          enable identity provider google
        }

        # Authorization policy: verify same key and set login URL
        authorization policy mypolicy {
          set auth url /auth
          crypto key verify {file.{$AUTH_SIGN_KEY_FILE}}
          allow email yonathan@gmail.com nosiri@gmail.com
        }
      }
    '';
    # https://caddyserver.com/docs/caddyfile/patterns#wildcard-certificates
    # To verify the converted json (with {$ENV} expanded), run curl localhost:2019/config/
    virtualHosts."*.yonathan.org".extraConfig = ''
      # Obtain a wildcard certificate for *.yonathan.org using DNS-01
      tls {
        # caddy has 2 types of interpolation that differ in when they are evaluated
        # apparently {file.{env.CLOUDFLARE_API_TOKEN_FILE}} does not work
        dns cloudflare {file.{$CLOUDFLARE_API_TOKEN_FILE}}
      }
      encode zstd gzip
      header {
        # Strict Transport Security (enable preload only if all subdomains are HTTPS)
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
      }

      @photos host photos.yonathan.org
      handle @photos {
        # Rate limit only auth endpoints, then proxy everything
        rate_limit {
          zone auth_zone {
            key {remote_host}
            events 3
            window 60s

            # POST on specific auth endpoints
            match {
              method POST
              path /api/auth/login /api/auth/admin-sign-up /api/auth/change-password /api/auth/session/unlock
            }

            # Any method on these endpoints
            match { path /api/auth/pin-code }
            match { path /api/shared-links/me }
          }
        }

        reverse_proxy 127.0.0.1:2283
      }

      @jellyfin host jellyfin.yonathan.org
      handle @jellyfin {
        # Rate limit only auth endpoints, then proxy everything
        rate_limit {
          zone auth_zone {
            key {remote_host}
            events 3
            window 60s

            # POST on specific auth endpoints
            match {
              method POST
              path /Users/authenticatebyname
            }
          }
        }

        reverse_proxy 127.0.0.1:8096
      }

      # Grafana
      @grafana host grafana.yonathan.org
      handle @grafana {
        reverse_proxy 127.0.0.1:3000
      }

      # Prometheus behind OIDC SSO (Google) using caddy-security
      # Mount portal endpoints (per plugin examples)
      route /auth* {
        authenticate * with myportal
      }

      # Do not apply authorizer to portal paths
      @prom_noauth {
        host prometheus.yonathan.org
        not path /auth*
      }
      handle @prom_noauth {
        route {
          authorize with mypolicy
          reverse_proxy 127.0.0.1:9090
        }
      }
    '';
  };
  # add a /etc/systemd/system/caddy.service.d/overrides.conf
  systemd.services.caddy = {
    # Provide Cloudflare API token via systemd credentials (TPM2-encrypted)
    # 1) Create /etc/secrets/cloudflare_token.cred using `systemd-creds encrypt --tpm2 -n cloudflare_token.cred ...`
    # 2) LoadCredentialEncrypted passes it to the service; systemd decrypts into $CREDENTIALS_DIRECTORY/cloudflare_token.cred
    # 3) preStart writes an EnvironmentFile read by Caddy with the token value
    serviceConfig.LoadCredentialEncrypted = [
      "cloudflare_token.cred:/etc/secrets/cloudflare_token.cred"
      # Google OIDC client credentials (TPM2-encrypted)
      "google_client_id:/etc/secrets/google_client_id"
      "google_client_secret:/etc/secrets/google_client_secret"
      # Signing key for caddy-security tokens
      "auth_sign_key:/etc/secrets/caddy_auth_sign_key.cred"
    ];
    # Use a dedicated runtime dir for caddy and place the envfile under $RUNTIME_DIRECTORY/caddy
    serviceConfig.RuntimeDirectory = "caddy";
    # Export the token directly from the decrypted credential into the environment
    # Expose credential file paths via %d, to avoid using the '@' expansion
    serviceConfig.Environment = [
      "CLOUDFLARE_API_TOKEN_FILE=%d/cloudflare_token.cred"
      "GOOGLE_CLIENT_ID_FILE=%d/google_client_id"
      "GOOGLE_CLIENT_SECRET_FILE=%d/google_client_secret"
      "AUTH_SIGN_KEY_FILE=%d/auth_sign_key"
    ];
  };

  # Enable TPM2 userspace stack so systemd can decrypt TPM2-sealed credentials
  # (doesn't work yet I don't think since sudo systemd-creds encrypt --tpm2-device --name=hi - -
  # still gives warning “Credential secret file '/var/lib/systemd/credential.secret' is not located on encrypted media, using anyway.”)
  security.tpm2.enable = true;

  # Enable sound.
  # sound.enable = true;
  # hardware.pulseaudio.enable = true;

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.yonran = {
    isNormalUser = true;
    extraGroups = [
      "wheel" # Enable ‘sudo’ for the user.
      "docker"
      "cdrom" # enable dvd drive
      "owntracks-recorder" # read owntracks-recorder database
    ];
    packages = with pkgs; [
      # firefox
      # tree
      git
      iotop
      dool
      smartmontools
      iperf
    ];
    openssh.authorizedKeys.keys = [
      # 2023 work laptop
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCiMP5A3V3xN+/nNGjCt6dVbFyfg1EYXxLNnkyu+8Q5fIoIodinKSd26joLIeSgbl9FJ4d27Y7aKLOyUVVRpluxbdATIwtIC+yEyOj0MZbak8oZCzi2rVki+APWEOFn9x/MOa+d5phYSbOD7Xo0UbhkH2q8ffHGhv3uPXdU4xctXPxlFkvXW/3XTnhJSpn1e18NUaMSzIj8/tpzbnSwjKyefXc2/YZ1tUovNMOLIocrzu0bnY6bqDtueZleOGf6a3rjR/41FGcdv4lZVXizdjVVNAuPcEN4l3+vIHYu3ZpCFwu9HTK+W9ImsDHKIYnVPuyk1KXm6GB1G2vhppE7dPVQAJqqdzjcwLYMaWy1dlM4YMl9l2XJkwBqwB5hiaNJttP8BjDq5qCAgi0a7b+VhGFBSq8LWD+eUeTXRjOmh/65o26TvPtBa9sB0jBMok4tdt/eg40gROt9ho6vdJ+7bVtg5sRy6Z0M1qQUDQli5HIzBKzwBmYA9kIAQs9T2CveJfk= yonran@Yonathans-MacBook-Pro.local"
      # pixel 6 ConnectBot
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDDqxHb38PL4CRl7bbYqeQ1ekXRX45iNo9/Ocsel5ar5AH31Va0fD2iBBtV22I/tHcIv4PrGX2vbTiumeG/oTLjThcQFZkqXthFnbDYeJ8+3fdeM9LcRcbt2G1vZmn+9hOSHNWAvfufpEgahHiZjJKOTIkKvhcNOGwsGh4CX+CZ7Vp3xq+tAaHTggczpJOzEPzfH/sBgXWA9+4v7eA+Kgw0Qu+Tkm2jZZjhyRD+PKie2UbodqZpI11rmCGFbS41ftA+kpcdy1QkS/Fa76uLSsW/3ejaKCcmVQKIZlOSJFWS48GEqr+SbWP1RA9FWiR9BpfOpE6S8oRylYzrZBOlEnKn pixel6"
    ];
  };
  # Samba-only user account (no shell login)
  users.users.nosiri = {
    isSystemUser = true;
    description = "Samba user nosiri";
    home = "/var/empty";
    createHome = false;
    shell = "${pkgs.shadow}/bin/nologin";
    group = "users";
  };
  security.sudo.wheelNeedsPassword = false;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    docker-compose
    ntfs3g
    tmux
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  # disable PasswordAuthentication after we added authorizedKeys above
  # Note that root is also prohibited by another default rule in /etc/ssh/sshd_config:
  # PermitRootLogin prohibit-password
  services.openssh.settings.PasswordAuthentication = false;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;


  # enable wake-on-lan, but netgear router does not have a way to wake
  networking.interfaces.enp7s0u2u4.wakeOnLan.enable = true;

  # don't sleep when the lid is shut (requires reboot)
  services.logind.lidSwitchExternalPower = "ignore";

  virtualisation.docker.enable = true;
  virtualisation.podman = {
    enable = true;
    # Required for containers under podman-compose to be able to talk to each other.
    defaultNetwork.settings.dns_enabled = true;
  };

  # Add system users for Immich
  users.groups.immich = { gid = 1001; };
  users.groups.immich-db = { gid = 1002; };

  users.users.immich = {
    isSystemUser = true;
    uid = 1001;
    group = "immich";
  };

  users.users.immich-db = {
    isSystemUser = true;
    uid = 1002;
    group = "immich-db";
  };


  # Immich services will start automatically via proper systemd dependencies

  # spin down spinning disks
  # https://www.reddit.com/r/NixOS/comments/751i5t/how_to_specify_that_hard_disks_should_spin_down/
  powerManagement.powerUpCommands = with pkgs; ''
    #TODO fix the quoting
    # ${bash}/bin/bash -c '${hdparm}/bin/hdparm -S 9 -B 127 $(${utillinux}/bin/lsblk -dnp -o name,rota |${gnugrep}/bin/grep \'.*\\s1\'|${coreutils}/bin/cut -d \' \' -f 1)'
  '';
  # services.udev.packages = [
  #   (pkgs.writeTextFile {
  #     name = "10-hdparm-sleep-disks.rules";
  #     destination = "/etc/udev/rules.d/10-hdparm-sleep-disks.rules";
  #     text = ''
  #       ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="<vendor>", ATTRS{idProduct}=="<product>" RUN+=""
  #     '';
  #   })
  # ];
  # extra udev rules which will be put in /etc/udev/rules.d/99-local.rules
  # for syntax see https://www.freedesktop.org/software/systemd/man/latest/udev.html
  # to list attributes of a device run sudo udevadm info -q all --attribute-walk /dev/sdd
  # To debug: sudo udevadm test -a add $(udevadm info -q path -n /dev/sda)
  services.udev.extraRules = ''
    # to debug these events: journalctl -eu systemd-udevd.service
    SUBSYSTEM=="block", ATTR{partition}!="1", OPTIONS="log_level=debug"
    # ATTR{partition}!="1": exclude partitions (e.g. sudo udevadm info -q all --attribute-walk /dev/sdd1)
    # ATTR{queue/rotational}=="1": match hard drives, exclude SSDs
    # TAG+="systemd": “systemd will dynamically create device units for all kernel devices that are marked with the "systemd" udev tag”
    #   https://www.freedesktop.org/software/systemd/man/latest/systemd.device.html
    # ENV{SYSTEMD_WANTS}+="hdparm-set@.service"
    #   specify unit names that will be started
    #   empty @ means that “it will be automatically instantiated by the device's "sysfs" path”
    #   https://www.freedesktop.org/software/systemd/man/latest/systemd.device.html
    # Note: you could have used "hdparm-set@%k.service", and then specify /dev/%I in the template file,
    # but SYSTEMD_WANTS supports this alternate method
    ACTION=="add", SUBSYSTEM=="block", ATTR{partition}!="1", TAG+="hdparmset", TAG+="systemd", ENV{SYSTEMD_WANTS}+="hdparm-set@%k.service"
  '';
  systemd.services."hdparm-set@" = {
    description = "Set hdparm -S 10 (sleep in 5s * 10) on newly added disks %I";
    serviceConfig.Type = "oneshot";
    serviceConfig.ExecStart = "${pkgs.hdparm}/bin/hdparm -S 10 /dev/%I";
  };

  services.owntracks-recorder.enable = true;


  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "23.11"; # Did you read the comment?

}
