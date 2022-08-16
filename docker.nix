let
  pkgs = import <nixpkgs> {
    system = "x86_64-darwin";
  };
in
  pkgs.mkShell {
    name = "docker";
    buildInputs = [
      pkgs.bashInteractive
      pkgs.docker
      # pkgs.docker-machine
      # pkgs.virtualbox
      pkgs.colima
      pkgs.lima # export it for debugging
      # and -v $(limactl shell colima printenv SSH_AUTH_SOCK):/ssh_auth.sock
      # https://github.com/rancher-sandbox/rancher-desktop/issues/2072#issue-1211536081
      # don't forget to colima start --ssh-agent
      # to get ssh credentials https://github.com/abiosoft/colima/issues/127
    ];
  shellHook = ''
      '';
  }
