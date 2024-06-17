# This is the configuration.nix for a Macbook Pro
# that I have converted to my personal server.
# To apply it, run `sudo nixos-rebuild switch`.

# This file (and hardware-configuration.nix) was originally generated
# by `nixos-generate-config` but I am customizing it 

# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./zfs-backup-module.nix
    ];
  # enable zfs-backup-module
  services.zfsBackup = {
    enable = true;
    source_pool = "firstpool";
    source_fs = "family";
    backup_pool = "backuppool";
    backup_fs = "family_backup";
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
  # time.timeZone = "Europe/Amsterdam";

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
  networking.interfaces.ens9.wakeOnLan.enable = true;

  # don't sleep when the lid is shut (requires reboot)
  services.logind.lidSwitchExternalPower = "ignore";

  virtualisation.docker.enable = true;

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

