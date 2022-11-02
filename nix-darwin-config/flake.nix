{
  description = "Yonathan's darwin system";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    # use my branch until this PR is merged
    # https://github.com/LnL7/nix-darwin/pull/491
    # darwin.url = "github:lnl7/nix-darwin/master";
    darwin.url = "github:yonran/nix-darwin/387-no-developer-tools-were-found";
    darwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, darwin, nixpkgs }: {
    # name the configurations x86_64 and aarch64
    # instead of the host name.
    # this means you have to darwin-rebuild switch --flake '.#aarch64'
    # instead of darwin-rebuild switch --flake .
    darwinConfigurations.x86_64 = darwin.lib.darwinSystem {
      system = "x86_64-darwin";
      modules = [ ./darwin-configuration.nix ];
    };
    darwinConfigurations.aarch64 = darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [ ./darwin-configuration.nix ];
    };
  };
}
