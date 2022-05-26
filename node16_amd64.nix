# amd64 to run x86_64 only native modules such as node-oracledb
# https://evanrelf.com/building-x86-64-packages-with-nix-on-apple-silicon
# This is like a nvm
# To create the environment within your CWD, run nix-shell node16.nix
# https://josephsdavid.github.io/nix.html
# https://churchman.nl/2019/01/22/using-nix-to-create-python-virtual-environments/
let
  pkgs = import <nixpkgs> {
    system = "x86_64-darwin";
  };
in
  pkgs.mkShell {
    name = "nodeEnv";
    buildInputs = [
      pkgs.bashInteractive
      pkgs.nodejs-16_x
      # python3 is needed for npm/node_modules/node-gyp/bin/node-gyp.js
      pkgs.python3
      # xcrun is needed for nodejs/lib/node_modules/npm/node_modules/node-gyp/pylib/gyp/xcode_emulation.py
      pkgs.xcbuild
    ];
    shellHook = ''
      export NPM_TOKEN=$(echo $'protocol=https\nhost=github.com\nusername=yonran' | git credential-osxkeychain get | cut -d= -f2)
      '';
  }
