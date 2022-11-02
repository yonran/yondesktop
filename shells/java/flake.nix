# Usage with .envrc: use flake ./shells/java#jdk8
{
  description = "Shells with JDK, maven, sbt";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils/master";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = nixpkgs.legacyPackages.${system};
      shellWithJdk = jdk: pkgs.mkShell {
        buildInputs = [
          jdk
          (pkgs.sbt.override {
            jre = jdk;
          })
          (pkgs.maven.override {
            inherit jdk;
          })

          # keep this line if you use bash
          pkgs.bashInteractive
        ];
      };
      in {
        devShells.jdk8 = shellWithJdk pkgs.openjdk8;
        devShells.jdk9 = shellWithJdk pkgs.openjdk9;
        devShells.jdk11 = shellWithJdk pkgs.openjdk11;
        devShells.jdk13 = shellWithJdk pkgs.openjdk13;
        devShells.jdk17 = shellWithJdk pkgs.openjdk17;
      }
    );
}
