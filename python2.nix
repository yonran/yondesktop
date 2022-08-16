# This is like virtualenv,
# To create the environment within your CWD, run nix-shell python.nix
# https://josephsdavid.github.io/nix.html
# https://churchman.nl/2019/01/22/using-nix-to-create-python-virtual-environments/
let
  pkgs = import <nixpkgs> {};
  my-python-packages = pkgs: [
    pkgs.pip
    pkgs.setuptools

  ];
  my-python = pkgs.python.withPackages my-python-packages;
in
  pkgs.mkShell {
    name = "simpleEnv";
    buildInputs = [
      pkgs.bashInteractive
      my-python
      pkgs.libmysqlclient # for contentsvc
      pkgs.openssl # for contentsvc
      pkgs.libffi # for contentsvc bcrypt
      pkgs.libxml2
      pkgs.libxslt
    ];
    # shellHook is executed by nix-shell in the PWD of that
    shellHook = ''
      export PIP_PREFIX="$(pwd)/env/pip_packages"
      export PYTHONPATH="$(pwd)/env/pip_packages/lib/python${my-python.pythonVersion}/site-packages" # :$PYTHONPATH 
      unset SOURCE_DATE_EPOCH
      '';
  }
