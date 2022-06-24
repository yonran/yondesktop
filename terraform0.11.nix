# To create the environment within your CWD, run nix-shell terraform1.1.nix
# tested with https://github.com/NixOS/nixpkgs/commit/2de556c4cd46a59e8ce2f85ee4dd400983213d45
# gotcha: after you terraform init, .terraform will store links to the providers
# even after the nix-shell ends, so make sure to terraform init after rebuilding!
{
  # tested on nixpkgs f96729212602f15a6a226d2f27f5de70492ad095 at least
  pkgs ? import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/f96729212602f15a6a226d2f27f5de70492ad095.tar.gz") {}
}:
let
  nullplugin = pkgs.terraform-providers.mkProvider {
    # last version of null plugin to work with terraform 0.11
    # in terraform-providers/default.nix, goPackagePath = "github.com/${data.owner}/${data.repo}"
    owner = "terraform-providers";
    provider-source-address = "registry.terraform.io/hashicorp/null";
    # goPackagePath is not hashicorp
    repo = "terraform-provider-null";
    rev = "v2.1.2";
    sha256 = "sha256-gsuEMAMqb1NtlSQDV8JcDvlVBIkCFwrR1wDp0WqHITY=";
    # vendorSha256 = null;
    version = "2.1.2";
  };
  aws = pkgs.terraform-providers.mkProvider {
    # in terraform-providers/default.nix, goPackagePath = "github.com/${data.owner}/${data.repo}"
    owner = "terraform-providers";
    provider-source-address = "registry.terraform.io/hashicorp/aws";
    repo = "terraform-provider-aws";
    rev = "v1.41.0";
    sha256 = "sha256-sLDsUb0XatVOadgcSdVVIq5cLS+obGm3ujRm+lce2MA=";
    # vendorSha256 = null;
    version = "1.41.0";
  };
  consul = pkgs.terraform-providers.mkProvider {
    owner = "terraform-providers";
    provider-source-address = "registry.terraform.io/hashicorp/consul";
    repo = "terraform-provider-consul";
    rev = "v2.2.0";
    sha256 = "sha256-08mYapydJhyUTo7lGvKESeGdqN2mJtz2v2iIY4/bXI4=";
    # vendorSha256 = null;
    version = "2.2.0";
  };
  consul215 = pkgs.terraform-providers.mkProvider {
    owner = "terraform-providers";
    provider-source-address = "registry.terraform.io/hashicorp/consul";
    repo = "terraform-provider-consul";
    rev = "v2.15.0";
    sha256 = "sha256-6NQL1ZlHZsxfoRV0zMOXApuCR+nj8CPWjpxj7BAJivY=";
    vendorSha256 = null;
    version = "2.15.0";
  };
  terraform_0_11 = pkgs.mkTerraform {
    version = "0.11.15";
    sha256 = "Fm2Notovy6hivwogYoPaxzOVK+Y5uWk7upWh8Pk/Gpc=";
    src = ~/third-party/golang/terraform;
    patches = [
      # use the patch used by terraform 0.12 that uses NIX_TERRAFORM_PLUGIN_DIR to set -plugin-dir
      <nixpkgs/pkgs/applications/networking/cluster/terraform/provider-path.patch>
      (pkgs.fetchpatch {
        name = "fix-mac-mojave-crashes.patch";
        url = "https://github.com/hashicorp/terraform/commit/cd65b28da051174a13ac76e54b7bb95d3051255c.patch";
        sha256 = "1k70kk4hli72x8gza6fy3vpckdm3sf881w61fmssrah3hgmfmbrs";
      })
      
    ];
    passthru = {
      plugins = removeAttrs pkgs.terraform-providers [
        "override"
        "overrideDerivation"
        "recurseForDerivations"
      ];
    };
  };
  terraform_with_plugins = terraform_0_11.withPlugins (p: [
    aws
    consul
    p.template
    consul215
    # p.null can't be used with 0.11: Incompatible API version with plugin. Plugin version: 5, Core version: 4
    nullplugin
  ]);
  shell = pkgs.mkShell {
    inherit terraform_0_11 aws;
    name = "nodeEnv";
    buildInputs = [
      pkgs.bashInteractive
      terraform_with_plugins
    ];
  shellHook = ''
      '';
  };
in shell
#                  relFile=''${file#$providerDir/}

