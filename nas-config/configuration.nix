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
      ./owntracks-recorder-service.nix
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
    allowedUDPPorts = [ 51820 ];
    # enable iperf
    allowedTCPPorts = [ 5201 ];
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
      };
    };
  };
  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };


  # Enable CUPS to print documents.
  # services.printing.enable = true;

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
      dstat
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
    description = "Set hdparm -S 10 on newly added disks %I";
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

