{
  pkgs ? import <nixpkgs> {}
, fetchFromGitHub ? pkgs.fetchFromGitHub
, buildGoPackage ? pkgs.buildGoPackage
, buildGoModule ? pkgs.buildGoModule
, lib ? pkgs.lib
, callPackage ? lib.callPackage
}:
buildGoModule rec {
  pname = "mcp-language-server";
  version = "0.1.1";
  src = fetchFromGitHub {
    owner = "isaacphi";
    repo = "mcp-language-server";
    rev = "v${version}";
    hash = "sha256-T0wuPSShJqVW+CcQHQuZnh3JOwqUxAKv1OCHwZMr7KM=";
  };
  vendorHash = "sha256-3NEG9o5AF2ZEFWkA9Gub8vn6DNptN6DwVcn/oR8ujW0=";
  # only build the main module. Without this, buildGoModule tries to find
  # each subdirectory and then fails trying to build subpackage ./integrationtests/workspaces/go
  subPackages = ".";
}
