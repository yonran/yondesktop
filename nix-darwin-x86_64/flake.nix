{
  description = "Yonathan's darwin system";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-22.05-darwin";
    darwin.url = "github:lnl7/nix-darwin/master";
    darwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, darwin, nixpkgs }: {
    darwinConfigurations."Yonathans-MacBook-Pro-2" = darwin.lib.darwinSystem {
      # system = "aarch64-darwin";
      system = "x86_64-darwin";
      modules = [ ./darwin-configuration.nix ];
    };
  };
}
