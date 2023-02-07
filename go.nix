let
  pkgs = import <nixpkgs> {};
in
  pkgs.mkShell {
    name = "go";
    buildInputs = [
      pkgs.bashInteractive
      pkgs.go
      pkgs.gopls
      pkgs.pkg-config
    ];
  shellHook = ''
      '';
  }
