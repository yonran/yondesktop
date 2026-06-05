# This is a home-manager config.
# home.nix is typically located at ~/.config/nixpkgs/home.nix
# https://nix-community.github.io/home-manager/index.html#ch-usage
# but with flakes we do
#   nix build --no-link .#homeConfigurations.x86_64.activationPackage
#   "$(nix path-info .#homeConfigurations.x86_64.activationPackage)"/activate
# or simply:
#   home-manager switch --flake '.#x86_64'
{ config, pkgs, lib, isWork ? false, ... }:

let
  username = "yonran";
in {
  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = username;
  home.homeDirectory = "/Users/${username}";

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

  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      enter_accept = true;
      search.filters = [ "session" "directory" "global" ];
    };
  };

  home.packages = [
    pkgs.python3
    pkgs.uv
    pkgs.git
    pkgs.ripgrep
    # pkgs.ripgrep-all
    pkgs.fd
    pkgs.tmux
    pkgs.jq
    pkgs.gh
    pkgs.nodejs_24
    pkgs.go
    pkgs.nixfmt
    pkgs.podman
    pkgs.podman-compose
    pkgs.uv
    (pkgs.rust-bin.stable.latest.default.override {
      extensions = [ "rust-src" ];
      targets = [ "x86_64-unknown-linux-gnu" "wasm32-unknown-unknown" ];
    })
    pkgs.wasm-pack
    pkgs.xcbuild
    pkgs.apple-sdk_14
    pkgs.clang
    # for getting the sha256 of fetchFromGitHub
    pkgs.nix-prefetch-github
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

  programs.direnv = {
    enable = true;

    # Add eval "$(direnv hook zsh)" to bash and zsh configs
    enableBashIntegration = true;
    enableZshIntegration = true;

    # install nix-direnv integrated into direnv to make use_nix faster and to add to gc roots
    # https://github.com/nix-community/nix-direnv
    nix-direnv.enable = true;
  };

  programs.git.enable = true;
  # configure ~/.config/git/config
  # (does not touch ~/.gitconfig, which is read later and can override these values)
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

    # Ignore claude code local settings .claude/*.local.* (but gitignore does not support multiple *)
    # https://code.claude.com/docs/en/settings
    "**/.claude/*.local.json"
    "**/.claude/*.local.md"
    # Boris Cherny suggestion: put worktrees in .claude https://x.com/bcherny/status/2017742743125299476
    "**/.claude/worktrees/"
    # my own random notes
    "*.local.md"
  ];
  programs.git.settings = {
    user.email = "yonathan@gmail.com";
    user.name = "Yonathan Randolph";
    rebase.autosquash = true;
    # Reject malformed/suspicious objects from remotes (catches a real but
    # rare class of supply-chain attack, and surfaces repo corruption early).
    #
    # When it fires, the error names the specific check, e.g.:
    #   error: object 5a3f...: zeroPaddedFilemode: contains zero-padded file modes
    #   fatal: fsck error in pack <hash>
    #
    # Common false positives are legacy data, not attacks:
    #   zeroPaddedFilemode   - old git wrote modes like "40000" instead of "040000"
    #                          (Linux kernel mirrors, old AOSP, pre-2010 repos)
    #   missingSpaceBeforeDate / badTimezone / missingEmail
    #                        - malformed commit metadata from old git versions
    #   nullSha1             - submodule pointer to 0000...0000
    #   missingTaggerEntry   - old tags without tagger field
    #
    # To handle a finding, downgrade the *specific* named check — never
    # disable fsckObjects wholesale. Three scopes, narrowest first:
    #   git -c fetch.fsck.zeroPaddedFilemode=warn clone <url>   # one-time
    #   git config fetch.fsck.zeroPaddedFilemode warn           # this repo
    #   # or in ~/.gitconfig:                                   # global
    #   #   [fetch "fsck"]
    #   #       zeroPaddedFilemode = warn
    # Values: error (default here), warn, ignore. Prefer `warn` over `ignore`.
    #
    # If receive.fsckObjects fires on push, *you* authored a malformed object
    # locally (usually via filter-branch / history rewrite). Investigate
    # before downgrading receive.fsck.<check>.
    transfer.fsckObjects = true;
    fetch.fsckObjects = true;
    receive.fsckObjects = true;
    # rewrite git urls to always use https;
    # save the GitHub credentials once in
    # git-credential-osxkeychain instead of having
    # another set of credentials in ~/.ssh
    url."https://github.com/".insteadOf = [
      "ssh://git@github.com/"
      # SCP-style form (e.g. `git@github.com:owner/repo.git`) is a separate
      # URL syntax from `ssh://git@github.com/...`, so it needs its own rule.
      "git@github.com:"
    ];
    # The nixpkgs darwin build of git ships a system gitconfig with
    # `credential.helper = osxkeychain`. credential.helper is multi-valued
    # and accumulates across system/global/local scopes, so without resetting
    # it osxkeychain still runs (and prompts the keychain) before gh is
    # consulted. An empty value clears any previously-collected helpers; the
    # per-host gh entries below then become the only helpers for github.com.
    #
    # To verify only gh is invoked (and not osxkeychain), feed a credential
    # query on stdin and watch the helper processes git spawns:
    #   printf 'protocol=https\nhost=github.com\n\n' | GIT_TRACE=1 git credential fill
    # Look for a `start_command` line naming `gh auth git-credential get`
    # and no `git-credential-osxkeychain` process. `git config --get-all
    # credential.helper` is NOT a valid check — it lists raw values from
    # every scope and does not simulate the empty-value reset.
    credential.helper = "";
    # set up credential helper to use gh; equivalent to gh auth setup-git:
    credential."https://github.com".helper = "!${pkgs.gh}/bin/gh auth git-credential";
    credential."https://gist.github.com".helper = "!${pkgs.gh}/bin/gh auth git-credential";
  };

  programs.bash.enable = true;
  # ~/.bashrc
  programs.bash.bashrcExtra = ''
  '';
  programs.bash.shellAliases = {
    docker = "podman";
    "docker-compose" = "podman-compose";
  };
  programs.zsh.enable = true;
  # ~/.zshrc
  programs.zsh.initContent = ''
    # make meta-backspace and meta-arrow move only to hyphen or slash like bash
    # https://unix.stackexchange.com/a/258661/9342
    autoload -U select-word-style
    select-word-style bash

    # xcbuild's xcrun doesn't follow symlinks in DEVELOPER_DIR,
    # so we must pass the realpath of ~/.nix-profile which contains
    # Platforms/ and Toolchains/ from pkgs.apple-sdk_14
    export DEVELOPER_DIR=$(realpath ~/.nix-profile)
  '';
  programs.zsh.shellAliases = {
    docker = "podman";
    "docker-compose" = "podman-compose";
  };
  programs.zsh.oh-my-zsh.enable = true;
  programs.zsh.oh-my-zsh.extraConfig = ''
  '';

  launchd.enable = true;


  # Create Grafana configuration directory and file
  # Skipped on the work laptop (isWork=true via the `work` flake output).
  xdg.configFile."grafana/grafana.ini" = lib.mkIf (!isWork) {
    text = ''
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
  };

  # LaunchAgent for macOS startup
  launchd.agents.grafana = lib.mkIf (!isWork) {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.grafana}/bin/grafana"
        "server"
        "-homepath" "${pkgs.grafana}/share/grafana"
        "-config" "${config.xdg.configHome}/grafana/grafana.ini"
      ];
      EnvironmentVariables = {
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
  # IMPORTANT: home-manager's `targets.darwin.defaults.<key>` writes to the
  # `defaults` domain literally named <key>. There are NO shortcuts — keys
  # like `trackpad`, `dock`, `finder`, `screencapture` create bogus domains
  # (e.g. `defaults read trackpad`) and do NOT touch the real `com.apple.*`
  # prefs. Always use the full domain name as a quoted attribute key.
  # Verify with: defaults read com.apple.<domain> <key>
  #
  # Built-in trackpad (defaults read com.apple.AppleMultitouchTrackpad)
  targets.darwin.defaults."com.apple.AppleMultitouchTrackpad" = {
    Clicking = true;
    TrackpadThreeFingerDrag = true;
    # macOS auto-disables conflicting three-finger gestures when three-finger
    # drag is on; pin them so they don't drift if drag is ever toggled off/on.
    TrackpadThreeFingerTapGesture = 0;
    TrackpadThreeFingerHorizSwipeGesture = 0;
    TrackpadThreeFingerVertSwipeGesture = 0;
  };
  # Magic Trackpad (Bluetooth) — separate domain from the built-in trackpad.
  targets.darwin.defaults."com.apple.driver.AppleBluetoothMultitouch.trackpad" = {
    Clicking = true;
    TrackpadThreeFingerDrag = true;
    TrackpadThreeFingerTapGesture = 0;
    TrackpadThreeFingerHorizSwipeGesture = 0;
    TrackpadThreeFingerVertSwipeGesture = 0;
  };
  # defaults read com.apple.screencapture disable-shadow
  targets.darwin.defaults."com.apple.screencapture".disable-shadow = true;

  # to refresh finder settings, killall Finder https://macos-defaults.com/finder/appleshowallextensions.html
  # defaults read com.apple.finder AppleShowAllFiles
  targets.darwin.defaults."com.apple.finder".AppleShowAllFiles = true;
  targets.darwin.defaults."com.apple.finder".ShowStatusBar = true;
  targets.darwin.defaults."com.apple.finder".AppleShowAllExtensions = true;

  # to refresh clock, killall SystemUIServer https://macos-defaults.com/menubar/flashdateseparators.html
  targets.darwin.defaults."com.apple.menuextra.clock".ShowSeconds = true;
  # to refresh, killall Dock https://macos-defaults.com/dock/orientation.html
  targets.darwin.defaults."com.apple.dock".orientation = "right";
  targets.darwin.currentHostDefaults."com.apple.controlcenter".BatteryShowPercentage = true;

  # Workaround for SSH StrictModes rejecting symlinks owned by root
  # https://github.com/nix-community/home-manager/issues/3090#issuecomment-3341948190
  # by GaspardCulis
  home.file.".ssh/authorized_keys_source" = {
    text = ''
      ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDDqxHb38PL4CRl7bbYqeQ1ekXRX45iNo9/Ocsel5ar5AH31Va0fD2iBBtV22I/tHcIv4PrGX2vbTiumeG/oTLjThcQFZkqXthFnbDYeJ8+3fdeM9LcRcbt2G1vZmn+9hOSHNWAvfufpEgahHiZjJKOTIkKvhcNOGwsGh4CX+CZ7Vp3xq+tAaHTggczpJOzEPzfH/sBgXWA9+4v7eA+Kgw0Qu+Tkm2jZZjhyRD+PKie2UbodqZpI11rmCGFbS41ftA+kpcdy1QkS/Fa76uLSsW/3ejaKCcmVQKIZlOSJFWS48GEqr+SbWP1RA9FWiR9BpfOpE6S8oRylYzrZBOlEnKn pixel 6 phone
      # 2026 work Macbook Pro
      ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC2ADlEL1SlpFiZsfrhm76K8h3wnVFgXX9D+pAeDfq38 yonran@Yonathans-MacBook-Pro.lan
    '';
    onChange = ''
      cat ~/.ssh/authorized_keys_source > ~/.ssh/authorized_keys
      rm ~/.ssh/authorized_keys_source
      chmod 600 ~/.ssh/authorized_keys
    '';
    force = true;
  };

  # npm configuration
  home.file.".npmrc".text = ''
    ignore-scripts=true
    # npm i -g should go to here instead of into /nix
    prefix=${config.home.homeDirectory}/.npm-global
  '';

  # yarn berry configuration
  home.file.".yarnrc.yml".text = ''
    enableScripts: false
  '';

  # pip configuration: refuse to install outside a virtualenv
  # (uv handles global tool installs; system pip should never touch site-packages)
  #
  # only-binary = :all: refuses source distributions, so a malicious package's
  # setup.py / pyproject.toml build hook cannot execute on `pip install`.
  # Wheels are pre-built and just unpacked, so no arbitrary code runs at install.
  #
  # Override when a package has no wheel (rare; common for git installs,
  # editable installs, niche packages):
  #   pip install --only-binary=:none: somepkg          # disable for one command
  #   pip install --no-binary=somepkg somepkg           # allow source for one package
  #   PIP_ONLY_BINARY=:none: pip install ...            # disable for a shell
  # Note: --no-binary alone does NOT override only-binary=:all:; you must use
  # --only-binary=:none: to actually empty the "binary-only" set.
  xdg.configFile."pip/pip.conf".text = ''
    [global]
    require-virtualenv = true
    only-binary = :all:
  '';

  home.sessionPath = [
    "${config.home.homeDirectory}/.npm-global/bin"
    "${config.home.homeDirectory}/.npm/bin"
    # claude code installs bin files here
    "${config.home.homeDirectory}/.local/bin"
  ];
}
