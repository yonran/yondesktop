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

let
  dvdbackup = pkgs.callPackage (pkgs.fetchFromGitHub {
    owner = "yonran";
    repo = "dvdbackup";
    rev = "b42f1efe10bea9a412de5a34b0a8ebe86db70fe3";
    sha256 = "sha256-fDAgFOGlL384a4s0GIzSFlkUSaGUUwzX+iJk3QsjBUg=";
  }) {};

  # 2025-11-16/2025-11-19/2025-11-23/2025-11-24/2025-11-25 logs show that when interface enp7s0u2u4 vanishes the TB chain is wedged in
  # runtime power-management: the root ports (0000:05:04.0/05:01.0) first report
  # "Unable to change power state from D3hot to D0, device inaccessible", then the USB NIC follows with
  # "r8152 ... NETDEV WATCHDOG ... Tx timeout"/"Stop submitting intr, status -108" and finally the XHCI dies.
  # Forcing only the child XHCI out of D3 (previous attempt) didn't help because the parent bridges had
  # already removed the entire hierarchy. This helper script now reproduces the manual rescue sequence:
  # toggle Thunderbolt authorization (as if we replugged the dock), forcibly remove the failing bridges
  # plus the XHCI function, and rescan PCI before giving up and rebooting.
  resetThunderboltXhci = pkgs.writeShellScript "reset-thunderbolt-xhci" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail
    IFACE="enp7s0u2u4"
    XHCI_DEV="0000:07:00.0"
    ROOT_PORTS=(0000:05:04.0 0000:05:02.0 0000:05:01.0)

    shopt -s nullglob
    TB_NODES=(/sys/bus/thunderbolt/devices/*-*)

    nic_up() {
      ${pkgs.iproute2}/bin/ip link show "$IFACE" > /dev/null 2>&1
    }

    log() { printf '%s\n' "$1"; }

    if nic_up; then
      exit 0
    fi

    log "network interface $IFACE missing; attempting Thunderbolt reset sequence"

    reset_tb_bus=false
    for node in "''${TB_NODES[@]}"; do
      if [ -w "$node/authorized" ]; then
        reset_tb_bus=true
        log "toggling Thunderbolt authorization on $(basename "$node")"
        printf '0\n' > "$node/authorized" || true
        sleep 1
        printf '1\n' > "$node/authorized" || true
      fi
    done
    $reset_tb_bus && sleep 2

    for dev in "''${ROOT_PORTS[@]}" "$XHCI_DEV"; do
      if [ -e "/sys/bus/pci/devices/$dev" ]; then
        log "removing PCI function $dev"
        printf '%s\n' "$dev" > "/sys/bus/pci/devices/$dev/remove" || true
      fi
    done

    sleep 2
    printf '1\n' > /sys/bus/pci/rescan
    log "PCI rescan triggered for Thunderbolt hierarchy"

    # Give udev time to rebuild the USB tree before deciding the recovery failed.
    sleep 8
    if nic_up; then
      log "interface $IFACE returned after Thunderbolt reset"
      exit 0
    fi

    log "recovery failed; rebooting to clear wedged Thunderbolt controller"
    ${pkgs.systemd}/bin/systemctl reboot
  '';

  hdparmSetScript = pkgs.writeShellScript "hdparm-set" ''
    DEVICE="$1"
    # Check if APM is supported, set it if so
    if ! ${pkgs.hdparm}/bin/hdparm -B "$DEVICE" 2>&1 | grep -q "not supported"; then
      ${pkgs.hdparm}/bin/hdparm -B 127 "$DEVICE"
    fi
    # Always set sleep timer
    ${pkgs.hdparm}/bin/hdparm -S 120 "$DEVICE"
  '';

  # Dyson integration for Home Assistant
  libdyson-neon = pkgs.home-assistant.python.pkgs.callPackage ./libdyson-neon.nix { };
  dyson-ha = pkgs.callPackage ./dyson-ha.nix {
    buildHomeAssistantComponent = pkgs.buildHomeAssistantComponent;
    inherit libdyson-neon;
  };
in
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
  # Socket buffer tuning for TCP over high-latency links
  #
  # Bandwidth-delay product: 52ms RTT × 5.35 MB/s upload = 278 KB minimum buffer.
  # Before tuning (131KB default): 400 KB/s. After (512KB+): 5 MB/s.
  # Test: ssh home.yonathan.org "dd if=/dev/zero bs=1M count=100" | dd of=/dev/null bs=1M
  #
  # Also set to 8MB for QUIC (quic-go wants 7MB per
  # https://github.com/quic-go/quic-go/wiki/UDP-Buffer-Sizes).
  # If too small, Caddy logs (see journalctl -u caddy):
  # “failed to increase receive buffer size (wanted: 7168 kiB, got XXX kiB)”
  boot.kernel.sysctl = {
    "net.core.rmem_max" = 8388608;         # 8MB max for all sockets (inc. TCP and UDP/QUIC)
    "net.core.wmem_max" = 8388608;         # 8MB max for all sockets
    "net.core.rmem_default" = 1048576;     # 1MB default for UDP (TCP uses tcp_rmem)
    "net.core.wmem_default" = 1048576;     # 1MB default for UDP (TCP uses tcp_wmem)
    "net.ipv4.tcp_rmem" = "4096 131072 8388608";  # TCP-specific: min default max
    "net.ipv4.tcp_wmem" = "4096 131072 8388608";  # TCP-specific: min default max
  };

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

  # Load software watchdog module (softdog) for system hang protection
  # Intel TCO hardware watchdog isn't available on this MacBook Pro hardware,
  # so we use softdog which provides kernel-level watchdog functionality
  boot.kernelModules = [ "softdog" ];
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
      8123 # home-assistant
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

  # This WD Caviar Green (WD10EADS) drive doesn't properly support the ATA STANDBY TIMER command (hdparm -S),
  # even though manual standby (hdparm -y) works immediately
  # and even though other drives in the same TDAS TerraMaster USB enclosure support hdparm -S.
  # So do not mount it by default.
  fileSystems."/stuff" = { device = "/dev/disk/by-uuid/508E-0B16"; options = ["noatime" "nofail" "noauto"]; };
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

  # Hardware watchdog configuration to auto-reboot on kernel hangs/freezes
  # Uses Intel TCO (Timer/Watchdog) hardware watchdog (iTCO_wdt module)
  # This will catch ZFS hangs, kernel panics, and complete system freezes
  # that the USB NIC watchdog (reset-thunderbolt-xhci) cannot detect
  systemd.watchdog = {
    runtimeTime = "30s";   # Ping watchdog every 30 seconds during normal operation
    rebootTime = "2min";   # Wait 2 minutes before forcing reboot if system doesn't respond
  };

  systemd.services.jellyfin = {
    requires = [ "firstpool-family.mount" ];
    after = [ "firstpool-family.mount" "local-fs.target" ];
    partOf = [ "firstpool-family.mount" ];
    unitConfig.RequiresMountsFor = "/firstpool/family";
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

  # Home Assistant - home automation platform
  # - Listens on 8123 (HTTP)
  # - Config stored in /var/lib/hass for persistence
  # - Access via Caddy reverse proxy at homeassistant.yonathan.org
  # - HACS (Home Assistant Community Store) auto-installed for custom integrations
  services.home-assistant = {
    enable = true;
    # Configure to work with Caddy reverse proxy
    config = {
      default_config = {};
      http = {
        use_x_forwarded_for = true;
        trusted_proxies = [ "127.0.0.1" "::1" ];
        # Allow access from reverse proxy
        server_host = "127.0.0.1";
      };
    };
    extraComponents = [
      # Common integrations you might want
      "met"  # Weather
      "mobile_app"  # Mobile app support
      "zeroconf"  # Auto-discovery
      "sun"  # Sun position
    ];
    # Custom components
    customComponents = [
      dyson-ha
    ];
  };

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Caddy reverse proxy for Immich over HTTPS with rate limiting plugin and HSTS
  services.caddy = {
    enable = true;
    email = "yonathan@gmail.com"; # ACME contact
    # Build Caddy with plugins
    # NOTE: pkgs.caddy.withPlugins and the hash below are specific to:
    #   NixOS version: 25.05.813768.fd0ca39c92fd (Warbler)
    #   nixpkgs commit: fd0ca39c92fd
    # To regenerate hash after updating NixOS/nixpkgs:
    #   1. Set hash to "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
    #   2. Run: sudo nixos-rebuild build 2>&1 | grep -A3 'hash mismatch'
    #   3. Update hash with the value shown in "got:"
    package = pkgs.caddy.withPlugins {
      plugins = [
        "github.com/mholt/caddy-ratelimit@v0.1.1-0.20250915152450-04ea34edc0c4"
        "github.com/caddy-dns/cloudflare@v0.2.3-0.20251204174556-6dc1fbb7e925"
        "github.com/greenpau/caddy-security@v1.1.31"
      ];
      hash = "sha256-Qw17KK2Og3/hHGKcVYGRnaDLXBBo4+xlSpPei4doyvg=";
    };
    # Global Caddyfile (must be first). Use globalConfig to emit it at top.
    globalConfig = ''
      debug
      # Disable HTTP/3 (QUIC) due to poor performance on high-latency links.
      # quic-go's loss detection (RFC 9002) interprets packet reordering as loss,
      # causing congestion control to back off and limiting throughput to ~35% of TCP.
      # See: https://github.com/quic-go/quic-go/issues/5325
      # With http2, we get 5MB/s downloading from Comcast Seattle to Comcast SF.
      # With http3, we only get 1MB/s (even with wmem_max)
      servers {
        protocols h1 h2
      }
      # Ensure plugin directives order well
      order authenticate before respond
      order authorize before reverse_proxy

      # Configure caddy-security app: Google OIDC portal and policy
      security {
        # Define Google OAuth2 IdP using shortcut (client_id client_secret)
        # TODO: caddy-security doesn't support {file.{$VAR}} syntax due to early parsing https://github.com/greenpau/caddy-security/issues/424
        # Should be: {file.{$GOOGLE_CLIENT_ID_FILE}} {file.{$GOOGLE_CLIENT_SECRET_FILE}}
        oauth identity provider google {file./run/credentials/caddy.service/google_client_id} {file./run/credentials/caddy.service/google_client_secret}

        # Authentication portal issues/validates tokens; requires a signing key
          authentication portal myportal {
            # Provide a signing key from file
            # TODO: caddy-security doesn't support {file.{$VAR}} syntax due to early parsing https://github.com/greenpau/caddy-security/issues/424
            # Should be: {file.{$AUTH_SIGN_KEY_FILE}}
            crypto key sign-verify {file./run/credentials/caddy.service/auth_sign_key}
            enable identity provider google
          }

        # Authorization policy: verify same key and set login URL
          authorization policy mypolicy {
            set auth url /auth/
            set redirect query parameter redirect_url
            # TODO: caddy-security doesn't support {file.{$VAR}} syntax due to early parsing https://github.com/greenpau/caddy-security/issues/424
            # Should be: {file.{$AUTH_SIGN_KEY_FILE}}
            crypto key verify {file./run/credentials/caddy.service/auth_sign_key}
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

      # Home Assistant
      @homeassistant host homeassistant.yonathan.org
      handle @homeassistant {
        # Rate limit auth endpoints to prevent brute force
        rate_limit {
          zone auth_zone {
            key {remote_host}
            events 5
            window 60s

            # POST on auth endpoints
            match {
              method POST
              path /auth/login_flow*
            }
          }
        }

        reverse_proxy 127.0.0.1:8123
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
    dvdbackup
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
  # to list env properties of a device run udevadm info -q property -n /dev/sdd
  # To debug: sudo udevadm test -a add $(udevadm info -q path -n /dev/sda)
  services.udev.extraRules = ''
    # to debug these events: journalctl -eu systemd-udevd.service
    SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", OPTIONS="log_level=debug"
    # ENV{DEVTYPE}=="disk": match only whole disks, not partitions (DEVTYPE=partition)
    #   DEVTYPE is set by the kernel in uevents (see sysfs(5) and /sys/block/*/uevent)
    #   https://man7.org/linux/man-pages/man5/sysfs.5.html
    # ATTR{queue/rotational}=="1": match hard drives, exclude SSDs
    # TAG+="systemd": “systemd will dynamically create device units for all kernel devices that are marked with the "systemd" udev tag”
    #   https://www.freedesktop.org/software/systemd/man/latest/systemd.device.html
    # ENV{SYSTEMD_WANTS}+="hdparm-set@.service"
    #   specify unit names that will be started
    #   empty @ means that “it will be automatically instantiated by the device's "sysfs" path”
    #   https://www.freedesktop.org/software/systemd/man/latest/systemd.device.html
    # Note: you could have used "hdparm-set@%k.service", and then specify /dev/%I in the template file,
    # but SYSTEMD_WANTS supports this alternate method
    ACTION=="add", SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", TAG+="hdparmset", TAG+="systemd", ENV{SYSTEMD_WANTS}+="hdparm-set@%k.service"
    # Prevent the Intel JHL6540 Thunderbolt controller (parent of the USB NIC/HDDs) from entering runtime D3.
    # Without this, the logs show "pcieport 0000:05:04.0: Unable to change power state from D3hot to D0, device inaccessible"
    # immediately followed by "xhci_hcd 0000:07:00.0: xHCI host controller not responding, assume dead".
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x15d4", TEST=="power/control", ATTR{power/control}="on"
    # The Nov 23/24/25 failures showed the bridges (05:01/05:02/05:04, vendor 0x8086/device 0x15d3) hit D3hot first,
    # so force them to stay "on" too; otherwise the XHCI fix alone has no effect because the parent bus vanishes.
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x15d3", TEST=="power/control", ATTR{power/control}="on"
  '';
  systemd.services."hdparm-set@" = {
    description = "Set hdparm -S 120 (sleep after 10 minutes) and -B 127 (APM) on newly added disks %I";
    serviceConfig.Type = "oneshot";
    serviceConfig.ExecStart = "${hdparmSetScript} /dev/%I";
  };

  # As a backstop for the "r8152 ... Stop submitting intr, status -108" failure this service invokes the
  # recovery script whenever the timer detects the NIC is missing. Earlier versions simply removed the
  # XHCI device and rebooted; the new script does the more complete Thunderbolt reset described above.
  systemd.services.reset-thunderbolt-xhci = {
    description = "Reset Thunderbolt-attached XHCI when USB NIC disappears";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = resetThunderboltXhci;
    };
  };

  # Periodically check so the service notices as soon as the watchdog errors / "Pool 'firstpool' has encountered an uncorrectable I/O failure"
  # sequence begins; the service exits immediately when healthy, so this just provides fast auto-heal without a reboot.
  systemd.timers.reset-thunderbolt-xhci = {
    description = "Periodic check to auto-recover Thunderbolt USB stack";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "1min";
      AccuracySec = "30s";
    };
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
