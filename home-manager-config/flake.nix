# to apply this flake-based home-manager config:
#   home-manager switch --flake '<flake-uri>#x86_64'
#   e.g. home-manager switch --flake ~/Documents/nixdesktop/home-manager-config#aarch64
# or
#   nix build --no-link <flake-uri>#homeConfigurations.x86_64.activationPackage
#   "$(nix path-info <flake-uri>#homeConfigurations.x86_64.activationPackage)"/activate
# https://nix-community.github.io/home-manager/index.html#sec-flakes-standalone
{
  description = "Home Manager configuration of Yonathan";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    # alternately, specify a branch:
    # nixpkgs.url = "github:NixOS/nixpkgs/nixos-22.05"
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      # alternately:
      # url = "github:nix-community/home-manager/release-22.05"
    };
  };

  outputs = { nixpkgs, home-manager, rust-overlay, ... }:
    let
      makeHomeConfiguration = system:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};

          # Specify your home configuration modules here, for example,
          # the pathni to your home.nix.
          modules = [
            ./home.nix
            # https://github.com/oxalica/rust-overlay
            ({ pkgs, ... }: {
              nixpkgs.overlays = [ rust-overlay.overlays.default ];
              # environment.systemPackages = [ pkgs.rust-bin.stable.latest.default ];
            })
          ];

          # Optionally use extraSpecialArgs
          # to pass through arguments to home.nix
        };
    in {
      homeConfigurations = {
        x86_64 = makeHomeConfiguration "x86_64-darwin";
        aarch64 = makeHomeConfiguration "aarch64-darwin";
      };
    };
}
