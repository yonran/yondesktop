{ config, pkgs, lib, ... }:

# This is the nix-darwin config, which is expected to exist
# in ~/.nixpkgs/darwin-configuration.nix
# (I symlinked it to there)

# To install nix-darwin:
# nix-build https://github.com/LnL7/nix-darwin/archive/master.tar.gz -A installer
# result/bin/darwin-installer

# To re-apply this config:
# darwin-rebuild switch

# This is a nix module which is automatically loaded by nix-darwin
# To evaluate in nix repl: :l <darwin>
# This is 
# lib.forEach config.environment.systemPackages (x: x.name)

{
  environment.variables = {
    # nix-darwin sets the default to nano
    EDITOR = "vim";
  };
  # List packages installed in system profile. To search by name, run:
  # https://nixos.org/manual/nixos/stable/index.html#sec-declarative-package-mgmt
  # $ nix-env -qaP | grep wget
  environment.systemPackages =
    [
      pkgs.vim
      pkgs.python3
      pkgs.git
      pkgs.ripgrep
      pkgs.fd
      pkgs.google-cloud-sdk
      pkgs.sbt
      pkgs.openjdk17
      pkgs.jq
      pkgs.gh
      pkgs.ripgrep-all
      pkgs.nixfmt
      pkgs.awscli2
      # pkgs.myawscli2
      # pkgs.mypackages
      # pkgs.python3.pkgs.jsonschema
      # (pkgs.python3.withPackages (p: [])).env
    ];
  nixpkgs.overlays = let overlayRemovePyopenssl = pkgs: super: 
    let removePyopenssl = debugLocation: pythonpkgs:
      let result = lib.filter
        (pythonpkg: !(pythonpkg != null && lib.hasAttr "pname" pythonpkg && pythonpkg.pname == "pyopenssl"))
        pythonpkgs;
      in lib.trace (lib.concatStrings [
        debugLocation
        ": "
        (toString (lib.length pythonpkgs))
        "->"
        (toString (lib.length result))
        " ("
        (lib.concatStringsSep ", " (map (x: if x == null then "null" else if lib.hasAttr "pname" x then x.pname else x.name) result))
        ")"
      ]) result;
    in {
      python3 = super.python3.override {
        # see https://nixos.org/manual/nixpkgs/stable/#how-to-override-a-python-package
        packageOverrides = python-self: python-super: rec {
          # workaround for
          # “Package ‘python3.10-pyopenssl-22.0.0’ in /nix/store/<hash>-nixpkgs/nixpkgs/pkgs/development/python-modules/pyopenssl/default.nix:73 is marked as broken, refusing to evaluate”
          # https://github.com/NixOS/nixpkgs/issues/174457
          # TODO: use overridePythonAttrs
          urllib3 = python-super.urllib3.overridePythonAttrs (origattrs: rec {
            propagatedBuildInputs = removePyopenssl "urllib3 propagatedBuildInputs" origattrs.propagatedBuildInputs;
          });
          cryptography = python-super.cryptography.overridePythonAttrs (old: rec {
            propagatedBuildInputs = old.propagatedBuildInputs ++  [python-self.six];
          });
          twisted = python-super.twisted.overridePythonAttrs (origattrs: {
            checkInputs = removePyopenssl "twisted checkInputs"  origattrs.checkInputs;
          });
          # jsonschema = python-super.jsonschema.override {twisted = python-self.twisted;};
        };
      };
      myawscli2 = (pkgs.awscli2.override {
        python3 = lib.trace 
          (lib.concatStrings [
            "myawscli2: urllib3="
            pkgs.python3.pkgs.urllib3
            "; dependencies: "
            (lib.concatStringsSep "," (lib.forEach pkgs.python3.pkgs.urllib3.propagatedBuildInputs (x: x.name)))
            " "

          ])
          pkgs.python3;
      }).overridePythonAttrs (old: rec {
        propagatedBuildInputs = removePyopenssl "awscli2 propagatedBuildInputs" old.propagatedBuildInputs;
        nativeBuildInputs = removePyopenssl "awscli2 nativeBuildInputs" old.nativeBuildInputs;
        passthru.mytest = "hi";
      });

    }; in
  [
    overlayRemovePyopenssl
  ];
  # TEMPORARY: allow awscli which does not work otherwise
  # nixpkgs.config.allowBroken = true;
  nixpkgs.config.packageOverrides = {
    # https://nixos.org/guides/nix-pills/nixpkgs-overriding-packages.html#idm140737319621760
    # However, the value pkgs.emacs in nixpkgs.config.packageOverrides
    # refers to the original rather than overridden instance,
    # to prevent an infinite recursion
    # https://nixos.org/manual/nixos/stable/index.html#sec-customising-packages
  };

  # Use a custom configuration.nix location.
  # $ darwin-rebuild switch -I darwin-config=$HOME/.config/nixpkgs/darwin/configuration.nix
  # environment.darwinConfig = "$HOME/.config/nixpkgs/darwin/configuration.nix";

  # Auto upgrade nix package and the daemon service.
  services.nix-daemon.enable = true;
  # nix.package = pkgs.nix;

  # Create /etc/bashrc that loads the nix-darwin environment.
  programs.zsh.enable = true;  # default shell on catalina
  # programs.fish.enable = true;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;
}
