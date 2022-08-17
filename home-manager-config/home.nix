# This is a home-manager config.
# home.nix is typically located at ~/.config/nixpkgs/home.nix
# https://nix-community.github.io/home-manager/index.html#ch-usage
# but with flakes we do
#   nix build --no-link .#homeConfigurations.x86_64.activationPackage
#   "$(nix path-info .#homeConfigurations.x86_64.activationPackage)"/activate
# or simply:
#   home-manager switch --flake '.#x86_64'
{ config, pkgs, lib, ... }:

let
  inherit (pkgs) lorri;
in {
  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "yonran";
  home.homeDirectory = "/Users/yonran";

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "22.05";

  # Let Home Manager install and manage itself.
  # programs.home-manager.enable = true;

  home.packages = [
    pkgs.vim
    pkgs.python3
    pkgs.direnv # for lorri
    pkgs.git
    pkgs.ripgrep
    pkgs.fd
    pkgs.google-cloud-sdk
    pkgs.sbt
    pkgs.openjdk17
    pkgs.visualvm
    pkgs.sbt
    pkgs.jq
    pkgs.gh
    pkgs.ripgrep-all
    pkgs.ocrmypdf
    pkgs.nixfmt
    pkgs.wifi-password
    pkgs.awscli2
    # proprietary ssm-session-manager-plugin is needed for
    # aws aws ssm start-session --region=us-west-2 --target=i-…
    pkgs.ssm-session-manager-plugin
    lorri
    # pkgs.myawscli2
    # pkgs.mypackages
    # pkgs.python3.pkgs.jsonschema
    # (pkgs.python3.withPackages (p: [])).env
  ];

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "ssm-session-manager-plugin"
  ];

  nixpkgs.overlays = let overlayRemovePyopenssl = self: super:
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
          # urllib3 already fixed in https://nixpk.gs/pr-tracker.html?pr=179159
          urllib3 = python-super.urllib3.overridePythonAttrs (origattrs: rec {
            propagatedBuildInputs = removePyopenssl "urllib3 propagatedBuildInputs" origattrs.propagatedBuildInputs;
          });
          twisted = python-super.twisted.overridePythonAttrs (origattrs: {
            checkInputs = removePyopenssl "twisted checkInputs"  origattrs.checkInputs;
          });
        };
      };
      myawscli2 = (super.awscli2.override {
        python3 = lib.trace 
          (lib.concatStrings [
            "myawscli2: urllib3="
            self.python3.pkgs.urllib3
            "; dependencies: "
            (lib.concatStringsSep ", " (lib.forEach self.python3.pkgs.urllib3.propagatedBuildInputs (x: x.pname)))
            " "

          ])
          self.python3;
      })
    #   .overridePythonAttrs (old: rec {
    #     propagatedBuildInputs = removePyopenssl "awscli2 propagatedBuildInputs" old.propagatedBuildInputs;
    #     # nativeBuildInputs = removePyopenssl "awscli2 nativeBuildInputs" old.nativeBuildInputs;
    #     passthru = old.passthru // {mytest = "hi";};
    #   })
      ;

    }; in
  [
    overlayRemovePyopenssl
  ];

  programs.vscode = {
    enable = true;
    package = pkgs.vscodium;
    extensions = [
      pkgs.vscode-extensions.bbenoist.nix
      pkgs.vscode-extensions.eamodio.gitlens
      pkgs.vscode-extensions.golang.go
      pkgs.vscode-extensions.rust-lang.rust-analyzer
    ];
  };

  # TEMPORARY: allow awscli which does not work otherwise
  # nixpkgs.config.allowBroken = true;
  nixpkgs.config.packageOverrides = {
    # https://nixos.org/guides/nix-pills/nixpkgs-overriding-packages.html#idm140737319621760
    # However, the value pkgs.emacs in nixpkgs.config.packageOverrides
    # refers to the original rather than overridden instance,
    # to prevent an infinite recursion
    # https://nixos.org/manual/nixos/stable/index.html#sec-customising-packages
  };

  programs.git.userEmail = "yonathan@gmail.com";
  programs.git.userName = "Yonathan Randolph";

  # direnv and lorri: see
  # https://nixos.wiki/wiki/Flakes#Direnv_integration
  # ~/.bashrc
  programs.bash.bashrcExtra = ''
    # https://direnv.net/docs/hook.html
    eval "$(direnv hook bash)"
  '';
  # ~/.zshrc
  programs.zsh.initExtra = ''
    # https://direnv.net/docs/hook.html
    eval "$(direnv hook zsh)"
  '';

  launchd.agents.lorri = {
    config = {
      # since lorri does not support on-demand launching on MacOS
      # using launchd_activate_socket(),
      # we have to hard-code the paths and KeepAlive always
      KeepAlive = true;
      RunAtLoad = true;
      ProgramArguments = ["${lorri}/bin/lorri" "daemon"];
    };
  };

  # MacOS Preferences
  # defaults read -globalDomain InitialKeyRepeat
  # Control Panel minimum InitialKeyRepeat is 15; I think 10 is better.
  targets.darwin.defaults.NSGlobalDomain.InitialKeyRepeat = 10;
  # Control Panel minimum KeyRepeat is 2
  targets.darwin.defaults.NSGlobalDomain.KeyRepeat = 2;
  targets.darwin.defaults.NSGlobalDomain.AppleShowScrollBars = "Always";
  # defaults read com.apple.AppleMultitouchTrackpad Clicking
  targets.darwin.defaults.trackpad.Clicking = true;
  targets.darwin.defaults.trackpad.TrackpadThreeFingerDrag = true;
  # defaults read com.apple.screencapture disable-shadow
  targets.darwin.defaults.screencapture.disable-shadow = true;
  # defaults read com.apple.finder AppleShowAllFiles
  targets.darwin.defaults.finder.AppleShowAllFiles = true;
  targets.darwin.defaults.finder.ShowStatusBar = true;
  targets.darwin.defaults.finder.AppleShowAllExtensions = true;
  targets.darwin.defaults.dock.orientation = "right";
}
