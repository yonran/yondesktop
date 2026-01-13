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
  sequelace = pkgs.callPackage ./sequelace.nix {};
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
    # bash history
    # fix super annoying bug where atuin selects wrong history entry when you press enter
    # https://github.com/atuinsh/atuin/pull/2715
    (pkgs.atuin.overrideAttrs (old: rec {
      version = "18.6.1";
      src = pkgs.fetchFromGitHub {
        owner = "atuinsh";
        repo = "atuin";
        rev = "v${version}";
        hash = "sha256-aRaUiGH2CTPtmbfrtLlNfoQzQWG817eazWctqwRlOCE";
      };
      cargoHash = if pkgs.stdenv.hostPlatform.isLinux then
        lib.fakeHash # TODO: set when I try on linux
      else
        "sha256-umagQYzOMr3Jh1RewjT0aX5FpYxs9N/70NZXoGaAfi4=";
      # recalculate cargoDeps since buildRustPackage calculates attributes that overrideAttrs does not automatically recalculate
      # https://github.com/NixOS/nixpkgs/blob/8ef82d9b1dd1df062acb74eba5928738d951facb/pkgs/build-support/rust/build-rust-package/default.nix#L91-L105
      cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
        inherit src;
        hash = cargoHash;
      };
    }))
    # pkgs.python3
    pkgs.direnv # for lorri
    pkgs.git
    pkgs.ripgrep
    # pkgs.ripgrep-all
    pkgs.fd
    pkgs.google-cloud-sdk
    pkgs.sbt
    pkgs.openjdk17
    pkgs.visualvm
    pkgs.tmux
    pkgs.jq
    pkgs.gh
    pkgs.nodejs_24
    # pkgs.ocrmypdf
    pkgs.nixfmt
    pkgs.awscli2
    (pkgs.rust-bin.selectLatestNightlyWith (toolchain: toolchain.default.override {
      extensions = [ "rust-src" ];
    }))
    # proprietary ssm-session-manager-plugin is needed for
    # aws aws ssm start-session --region=us-west-2 --target=i-…
    pkgs.ssm-session-manager-plugin
    lorri
    # for getting the sha256 of fetchFromGitHub
    pkgs.nix-prefetch-github
    # pkgs.myawscli2
    # pkgs.mypackages
    # pkgs.python3.pkgs.jsonschema
    # (pkgs.python3.withPackages (p: [])).env
    sequelace
    # temporarily install go globally until vscode-go
    # handles direnv properly
    # https://github.com/golang/vscode-go/issues/2617
    pkgs.go
    pkgs.gopls
  ];

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "ssm-session-manager-plugin"
  ];

  programs.vim = {
    enable = true;
    plugins = with pkgs.vimPlugins; [ ];
    #settings = { ignorecase = true; };
    extraConfig = ''
      " set mouse=a
      " https://stackoverflow.com/a/57918829/471341
      " set clipboard=unnamed
    '';
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

  home.sessionVariables = {
    # expose rust-src to fix vscode rust-analyzer error
    # rust-analyzer failed to load workspace: Failed to find sysroot for Cargo.toml file /Users/yonran/arena/mysql-proxy/Cargo.toml. Is rust-src installed?: can't load standard library from sysroot /nix/store/ml6i1rd72qdc66vnvpadqn3yxrz7isbl-rustc-1.64.0 (discovered via `rustc --print sysroot`) try installing the Rust source the same way you installed rustc
    # https://discourse.nixos.org/t/rust-src-not-found-and-other-misadventures-of-developing-rust-on-nixos/11570/6
    # RUST_SRC_PATH="${pkgs.rust-src}/lib/rustlib/src/rust/library/";
  };


  programs.git.enable = true;
  # configure ~/.config/git/config
  # (does not touch ~/.gitconfig, which is read later and can override these values)
  programs.git.userEmail = "yonathan@gmail.com";
  programs.git.userName = "Yonathan Randolph";
  programs.git.ignores = [
    # direnv layout dir used for isolated GOPATH, python venv, nix flake
    # https://github.com/direnv/direnv/blob/v2.32.2/stdlib.sh#L113-L122
    ".direnv/"
    ".vscode/"
    ".terrafirma/"
    ".terraform/"
    "terraform.tfstate.*.backup"
    "terraform.tfstate"
    "terraform.tfstate.d/"
    ".pytype/"
    ".metals/" # scala IDE files
    ".DS_Store"

    # most of the time I don't want to check in nix files
    ".envrc"
    "shell.nix"
  ];
  programs.git.extraConfig = {
    rebase = {
      autosquash = true;
    };
    # rewrite git urls to always use https;
    # save the GitHub credentials once in
    # git-credential-osxkeychain instead of having
    # another set of credentials in ~/.ssh
    url."https://github.com/".insteadOf = "ssh://git@github.com/";
    # set up credential helper to use gh; equivalent to gh auth setup-git:
    credential."https://github.com".helper = "!${pkgs.gh}/bin/gh auth git-credential";
    credential."https://gist.github.com ".helper = "!${pkgs.gh}/bin/gh auth git-credential";
  };

  programs.bash.enable = true;
  # direnv and lorri: see
  # https://nixos.wiki/wiki/Flakes#Direnv_integration
  # ~/.bashrc
  programs.bash.bashrcExtra = ''
    # https://direnv.net/docs/hook.html
    eval "$(direnv hook bash)"
  '';
  programs.zsh.enable = true;
  # ~/.zshrc
  programs.zsh.initExtra = ''
    # https://github.com/ellie/atuin#zsh
    eval "$(atuin init zsh)"

    # https://direnv.net/docs/hook.html
    eval "$(direnv hook zsh)"

    # make meta-backspace and meta-arrow move only to hyphen or slash like bash
    # https://unix.stackexchange.com/a/258661/9342
    autoload -U select-word-style
    select-word-style bash
  '';
  programs.zsh.oh-my-zsh.enable = true;
  programs.zsh.oh-my-zsh.extraConfig = ''
  '';

  launchd.enable = true;
  launchd.agents.lorri = {
    enable = true;
    config = {
      # since lorri does not support on-demand launching on MacOS
      # using launchd_activate_socket(),
      # we have to hard-code the paths and KeepAlive always
      KeepAlive = true;
      RunAtLoad = true;
      ProgramArguments = ["${lorri}/bin/lorri" "daemon"];
    };
  };


  # Create Grafana configuration directory and file
  xdg.configFile."grafana/grafana.ini".text = ''
    [server]
    http_port = 3000
    http_addr = ::1

    # [security]
    # admin_user = admin
    # admin_password = $ADMIN_PASSWORD

    [paths]
    data = ${config.xdg.dataHome}/grafana/data
    logs = ${config.xdg.dataHome}/grafana/logs
    plugins = ${config.xdg.dataHome}/grafana/plugins
  '';

  # LaunchAgent for macOS startup
  launchd.agents.grafana = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.grafana}/bin/grafana"
        "server"
        "-homepath" "${pkgs.grafana}/share/grafana"
        "-config" "${config.xdg.configHome}/grafana/grafana.ini"
      ];
      EnvironmentVariables = {
        AWS_SDK_LOAD_CONFIG= "1"; # load ~/.aws/config
        AWS_PROFILE = "say";
      };
      KeepAlive = true;
      RunAtLoad = true;
      # avoid warning
      # “Background Items Added” “"grafana" is an item that can run in the background. You can manage this in Login Items Settings.”
      ProcessType = "Background";

      StandardOutPath = "${config.xdg.dataHome}/grafana/logs/stdout.log";
      StandardErrorPath = "${config.xdg.dataHome}/grafana/logs/stderr.log";
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

  targets.darwin.defaults.activationScripts.extraUserActivation = ''
    # Settings -> Keyboard -> Shortcuts -> App Shortcuts
    # @=⌘, ~=⌥Option ^=Control, $=⇧Shift
    defaults write NSGlobalDomain NSUserKeyEquivalents -dict-add "Move Window to Left Side of Screen" '@^\U2190'
    defaults write NSGlobalDomain NSUserKeyEquivalents -dict-add "Move Window to Right Side of Screen" '@^\U2192'
    # Catalina hover on green full-screen button https://support.apple.com/en-us/HT204948
    defaults write NSGlobalDomain NSUserKeyEquivalents -dict-add "Tile Window to Left of Screen" '@~^\U2190'
    defaults write NSGlobalDomain NSUserKeyEquivalents -dict-add "Tile Window to Right of Screen" '@~^\U2192'

    defaults write com.apple.menuextra.clock -dict-add ShowSeconds 1
  '';
}
