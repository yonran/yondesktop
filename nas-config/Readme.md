This is the NixOS config for a home server using a 2015 Macbook Pro.

## NixOS Installation steps:

1. Download Minimal ISO Image from [NixOS ISOs](https://nixos.org/download#nixos-iso):
Minimal ISO Image
([NixOS Manual: Installation: Obtaining NixOS](https://nixos.org/manual/nixos/stable/#sec-obtaining)).
2. Copy ISO to a flash disk using
`sudo dd if=/tmp/nixos-minimal-VERSION-linux.iso  of=/dev/rdiskNN bs=4M conv=fsync status=progress`
([NixOS Manual: Installation: Additional installation notes: Booting from a USB flash drive](https://nixos.org/manual/nixos/stable/#sec-booting-from-usb)).
**Add `status=progress`** to show status bar in gnu coreutils 8.24+.
3. Plug in Thunderbolt to **Ethernet adapter** because the ISO does not have
the nonfree wifi adapter `config.boot.kernelPackages.broadcom_sta` enabled.
4. Boot from USB stick
([NixOS Manual: Installation: Booting from the install medium](https://nixos.org/manual/nixos/stable/#sec-installation-booting)).
5. Partition the SSD
([NixOS Manual: Installation: Partitioning and formatting](https://nixos.org/manual/nixos/stable/#sec-installation-manual-partitioning))
  ```
  sudo parted /dev/nvme0n1 -- print
  # remove the MacOS partition 2. No need to repartition 1 (EFI System Partition)
  sudo parted /dev/nvme0n1 -- rm 2
  sudo parted /dev/nvme0n1 -- mkpart root ext4 211MB -16GB
  sudo parted /dev/nvme0n1 -- mkpart swap linux-swap -16GB 100%
  ```
6. Format the SSD
([NixOS Manual: Installation: Partitioning and formatting](https://nixos.org/manual/nixos/stable/#sec-installation-manual-partitioning)).
  ```
  # No need to reformat partition 1 (EFI System Partition) which is already FAT
  sudo mkfs.ext4 -L nixos /dev/nvme0n1p2
  sudo mkswap -L swap /dev/nvme0n1p3
  ```
7. Mount big partition to `/mnt`, UEFI partition to `/mnt/boot`
([NixOS Manual: Installation: Installing](https://nixos.org/manual/nixos/stable/#sec-installation-manual-installing)).
  ```
  mount /dev/nvme0n1p2 /mnt
  mount /dev/nvme0n1p1 /mnt/boot
  ```
8. Create /mnt/etc/nixos/hardware-configuration.nix and /mnt/etc/nixos/configuration.nix
([NixOS Manual: Installation: Installing](https://nixos.org/manual/nixos/stable/#sec-installation-manual-installing)).
  ```
  nixos-generate-config
  ```
9. Edit `/mnt/etc/nixos/configuration.nix`: add `nixpkgs.config.allowUnfree = true`
so that broadcom_sta module can load
10. Install NixOS packages `nixos-install`
([NixOS Manual: Installation: Installing](https://nixos.org/manual/nixos/stable/#sec-installation-manual-installing))
11. Change `configuration.nix` to allow SSHing to machine and then run
`sudo nixos-rebuild switch`:
  * Set `networking.hostName = "yonnas";` to something unique
  * Enable SSH server
    ```
    services.openssh.enable = true;
    services.openssh.settings.PasswordAuthentication = true;
    ```
  * Define a non-root user (by default, SSH does not allow root password ssh)
    ```
    users.users.yonran = {
      isNormalUser = true;
      extraGroups = [ "wheel" ]; # Enable ‘sudo’
    }
    ```
  * Enable Bonjour mDNS so you can discover yonnas.local
    ```
    services.avahi.enable = true;
    services.avahi.publish = {
      enable = true;
      addresses = true; # publish the IP address of this machine
      workstation = true; # publish the machine as a workstatino, which includes the hostname
    };
    ```
  * Enable wifi
    ```
    networking.networkmanager.enable = true;
    ```
12. Set a password for the non-root user (`sudo passwd yonran`)
13. Join a network:
  ```
  nmcli device wifi list
  sudo nmcli connection add con-name NAME type wifi ssid SSID
  sudo nmcli connection up NAME --ask
  ```
14. Then use another machine to `ssh yonran@yonnas.local` and do the rest remotely.
  ```
  rsync --rsync-path="sudo rsync" configuration.nix yonran@yonnas.local:/etc/nixos/configuration.nix &&
  ssh yonran@yonnas.local -- sudo nixos-rebuild switch
  ```

## Configure sb-exporter

To configure the monitoring of the cable sb-exporter modem monitor,
add a systemd EnvironmentFile to /etc/sb-exporter.env:

```
MODEM_PASSWORD=password
```
