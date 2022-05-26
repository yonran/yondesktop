# Issues with podman:
# 1) podman machine start failure “Error: dial unix /var/folders/v8/SHA/T/podman/podman-machine-default_ready.sock: connect: connection refused”; see fix for podman machine start with nix: vim ~/.config/containers/podman/machine/qemu/podman-machine-default.json and set -drive file=… to absolute path
# 2) podman machine can't run amd64 images (exec error);
# podman machine ssh
# sudo rpm-ostree install qemu-user-static --reboot
# https://github.com/containers/podman/discussions/12899
let
  pkgs = import <nixpkgs> {
  };
  podmanPackage = pkgs.podman;
  dockerCompat = pkgs.runCommand "docker-compat" {
    outputs = [ "out" "man" ];
    inherit (podmanPackage) meta;
  } ''
    # copied from nixos
    # https://github.com/NixOS/nixpkgs/blob/22.05-beta/nixos/modules/virtualisation/podman/default.nix#L19-L26
    mkdir -p $out/bin
    ln -s ${podmanPackage}/bin/podman $out/bin/docker

    mkdir -p $man/share/man/man1
    for f in ${podmanPackage.man}/share/man/man1/*; do
      basename=$(basename $f | sed s/podman/docker/g)
      ln -s $f $man/share/man/man1/$basename
    done
  '';
in
  pkgs.mkShell {
    name = "podman";
    buildInputs = [
      pkgs.bashInteractive
      podmanPackage
      pkgs.podman-compose
      dockerCompat
    ];
    shellHook = ''
      '';
  }
