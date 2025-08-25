{
  pkgs ? import <nixpkgs> {}
, fetchFromGitHub ? pkgs.fetchFromGitHub
, buildGoPackage ? pkgs.buildGoPackage
, buildGoModule ? pkgs.buildGoModule
, lib ? pkgs.lib
, callPackage ? lib.callPackage
}:
buildGoModule rec {
  pname = "ssmps";
  version = "0.1.2";
  # copied from deps.nix
  src = fetchFromGitHub {
    owner = "stanimoto";
    repo = "consul-template-aws-ssmps";
    rev = "v${version}";
    hash = "sha256-St2oGePWL5p69q8/hpVl+QjQ9Z3SdAqaiEPHiusGItI=";
  };
  vendorHash = "sha256-uc6cS98wsCaijJDk50IO8CqCXNuoxjoTY/ZXrl3qqTw=";
  postFixup = ''
  mv $out/bin/consul-template-aws-ssmps $out/bin/ssmps
  '';
}
