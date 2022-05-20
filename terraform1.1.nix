# To create the environment within your CWD, run nix-shell terraform1.1.nix
let
  pkgs = import <nixpkgs> {};
in
  pkgs.mkShell {
    name = "nodeEnv";
    buildInputs = [
      pkgs.bashInteractive
      pkgs.terraform
    ];
  shellHook = ''
      '';
  }
