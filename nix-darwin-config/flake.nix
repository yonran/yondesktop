{
  description = "Yonathan's darwin system";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    darwin.url = "github:lnl7/nix-darwin/master";
    # testing
    # darwin.url = "/Users/yonran/third-party/nix/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs";
    flake-utils.url = "github:numtide/flake-utils/main";
  };

  outputs = { self, darwin, nixpkgs, flake-utils }: flake-utils.lib.eachDefaultSystem (system:
    let pkgs = nixpkgs.legacyPackages.${system};
    in {
      darwinConfigurations.default = darwin.lib.darwinSystem {
        inherit system;
        modules = [ ./darwin-configuration.nix ];
      };
    }
  );
}
