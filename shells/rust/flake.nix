# Usage with .envrc: use flake ./shells/rust#default
# Usage with flake: nix develop ./shells/rust#default
{
  description = "Shells with cargo, rustc, rust-src";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils/main";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.pkg-config
            # expose rust-src to fix vscode rust-analyzer error
            # rust-analyzer failed to load workspace: Failed to find sysroot for Cargo.toml file /Users/yonran/arena/mysql-proxy/Cargo.toml. Is rust-src installed?: can't load standard library from sysroot /nix/store/ml6i1rd72qdc66vnvpadqn3yxrz7isbl-rustc-1.64.0 (discovered via `rustc --print sysroot`) try installing the Rust source the same way you installed rustc
            (pkgs.rust-bin.beta.latest.default.override {
              extensions = [ "rust-src" ];
            })
          ];

          # expose rust-src to fix vscode rust-analyzer error
          # rust-analyzer failed to load workspace: Failed to find sysroot for Cargo.toml file /Users/yonran/arena/mysql-proxy/Cargo.toml. Is rust-src installed?: can't load standard library from sysroot /nix/store/ml6i1rd72qdc66vnvpadqn3yxrz7isbl-rustc-1.64.0 (discovered via `rustc --print sysroot`) try installing the Rust source the same way you installed rustc
          # https://discourse.nixos.org/t/rust-src-not-found-and-other-misadventures-of-developing-rust-on-nixos/11570/6
          RUST_SRC_PATH = "${pkgs.rust.packages.stable.rustPlatform.rustLibSrc}";

          shellHook = ''
          '';
        };
      }
    );
}
