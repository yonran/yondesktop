# This is like virtualenv,
# To create the environment within your CWD, run nix-shell python.nix
# https://josephsdavid.github.io/nix.html
# https://churchman.nl/2019/01/22/using-nix-to-create-python-virtual-environments/
let
  pkgs = import <nixpkgs> {};
  my-python-packages = python-packages: [
    python-packages.pip
  ];
  my-python = pkgs.python310.withPackages my-python-packages;
in
  pkgs.mkShell {
    name = "simpleEnv";
    buildInputs = [
      pkgs.bashInteractive
      my-python
    ];
    # shellHook is executed by nix-shell in the PWD of that
    shellHook = ''
      export PIP_PREFIX="$(pwd)/env/pip_packages"
      export PYTHONPATH="$(pwd)/env/pip_packages/lib/${my-python.pythonVersion}/site-packages" # :$PYTHONPATH 
      unset SOURCE_DATE_EPOCH
      '';
  }
