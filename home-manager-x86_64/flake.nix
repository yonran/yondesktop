# to apply this flake-based home-manager config:
#   home-manager switch --flake '<flake-uri>#yonran'
# or
#   nix build --no-link <flake-uri>#homeConfigurations.yonran.activationPackage
#   "$(nix path-info <flake-uri>#homeConfigurations.yonran.activationPackage)"/activate
# https://nix-community.github.io/home-manager/index.html#sec-flakes-standalone
{
  description = "Home Manager configuration of Yonathan";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    # alternately, specify a branch:
    # nixpkgs.url = "github:NixOS/nixpkgs/nixos-22.05"
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      # alternately:
      # url = "github:nix-community/home-manager/release-22.05"
    };
  };

  outputs = { nixpkgs, home-manager, ... }:
    let
      # system = "aarch64-darwin";
      system = "x86_64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      homeConfigurations.yonran = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        # Specify your home configuration modules here, for example,
        # the path to your home.nix.
        modules = [
          ./home.nix
        ];

        # Optionally use extraSpecialArgs
        # to pass through arguments to home.nix
      };
    };
}
