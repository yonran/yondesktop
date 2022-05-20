# This is like a nvm
# To create the environment within your CWD, run nix-shell node16.nix
# https://josephsdavid.github.io/nix.html
# https://churchman.nl/2019/01/22/using-nix-to-create-python-virtual-environments/
let
  pkgs = import <nixpkgs> {};
in
  pkgs.mkShell {
    name = "nodeEnv";
    buildInputs = [
      pkgs.bashInteractive
      pkgs.nodejs-16_x
    ];
    shellHook = ''
      '';
  }
