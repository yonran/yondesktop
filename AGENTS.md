The home server is attached to a wifi router with NAT (which also provides dyndns home.yonathan.org) and internet using Comcast. Therefore, to connect, just do `ssh home.yonathan.org`. Note that you can’t access `yonnas.local` unless we happen to be at home.

On the router, ssh, http, https, and wireguard are port forwarded to the home server (e.g. caddy). But other services (e.g. samba-smbd) must be accessed through wireguard. The server IP address is 192.168.29.3.

The home server runs nixos. See nas-config/configuration.nix. I keep it in sync with this laptop using `rsync -r --delete --exclude=hardware-configuration.nix --rsync-path="sudo rsync" ~/Documents/nixdesktop/nas-config/ yonran@home.yonathan.org:/etc/nixos/ && ssh yonran@home.yonathan.org -- sudo nixos-rebuild switch`.

All the important data is stored in `/firstpool/family`, which is a password-encrypted ZFS mount.

The server has a USB C hub which provides the Ethernet plug to the router and USB 3.0 plug that the hard drives are connected to. But this USB C hub is flaky and often breaks; see reset-thunderbolt-xhci in nas-config/configuration.nix for an experimental watchdog that resets it periodically.
