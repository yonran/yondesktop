{ config, pkgs, lib, ... }:

# to apply this flake-based nix-darwin config:
#   (do this within nix-shell -p git)
#   nix --experimental-features 'nix-command flakes' build '.#darwinConfigurations.aarch64.system'
#   # the following step may be needed to bootstrap 
#   source ./result/sw/bin/darwin-rebuild activate --flake '.#aarch64'
#   ./result/sw/bin/darwin-rebuild switch --flake '.#aarch64'
# once built, you can rebuild with
#   darwin-rebuild switch --flake '.#aarch64'
# https://github.com/LnL7/nix-darwin/tree/54a24f042f93c79f5679f133faddedec61955cf2#flakes-experimental

# Previous instructions (pre-flakes)
#   This is the nix-darwin config, which is expected to exist
#   in ~/.nixpkgs/darwin-configuration.nix
#   (I symlinked it to there)
# 
#   To install nix-darwin:
#   nix-build https://github.com/LnL7/nix-darwin/archive/master.tar.gz -A installer
#   result/bin/darwin-installer
# 
#   To re-apply this config:
#   darwin-rebuild switch
# 
#   This is a nix module which is automatically loaded by nix-darwin
#   To evaluate in nix repl: :l <darwin>
#   lib.forEach config.environment.systemPackages (x: x.name)

{
  imports = [];

  environment.variables = {
    # nix-darwin sets the default to nano
    EDITOR = "vim";
  };
  # List packages installed in system profile. To search by name, run:
  # https://nixos.org/manual/nixos/stable/index.html#sec-declarative-package-mgmt
  # $ nix-env -qaP | grep wget
  environment.systemPackages =
    [
      pkgs.home-manager
      pkgs.git # needed for nix commands
    ];

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

  # see https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/misc/nix-daemon.nix
  # /etc/nix/nix.conf
  nix.package = pkgs.nixUnstable; # required for experimental-features
  nix.extraOptions = ''
    # enable flakes
    experimental-features = nix-command flakes
  '';
}
