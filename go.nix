let
  pkgs = import <nixpkgs> {};
in
  pkgs.mkShell {
    name = "go";
    buildInputs = [
      pkgs.bashInteractive
      pkgs.go
      pkgs.pkg-config
    ];
  shellHook = ''
      '';
  }
