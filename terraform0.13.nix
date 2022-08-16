# not working yet
# To create the environment within your CWD, run nix-shell terraform0.13.nix
# gotcha: after you terraform init, .terraform will store links to the providers
# even after the nix-shell ends, so make sure to terraform init after rebuilding!
# nix-shell ~/Documents/nixdesktop/terraform0.13.nix -I https://github.com/NixOS/nixpkgs/archive/dc08c93d54f4f49cb73b33913bde75ccda54b32c.tar.gz
{
  # terraform_0_13 was removed here:
  # https://github.com/NixOS/nixpkgs/commit/584db216dba55ec77ffb469f4efc0cb25dc824f0
  pkgs ? import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/dc08c93d54f4f49cb73b33913bde75ccda54b32c.tar.gz") {}
}:
let
  aws = pkgs.terraform-providers.mkProvider {
    # in terraform-providers/default.nix, goPackagePath = "github.com/${data.owner}/${data.repo}"
    owner = "terraform-providers";
    provider-source-address = "registry.terraform.io/hashicorp/aws";
    repo = "terraform-provider-aws";
    rev = "v3.45.0";
    sha256 = "sha256-aLaZmqclMxZPjc06Q8JPwjL/dHQ52YtBn8GMQqnsEA0=";
    vendorSha256 = "sha256-qFEZ2i6FNTVC2Wy3mFCU/mAkR+XwEgo/hTW1eG5EnUg=";
    version = "3.45.0";
  };
  consul = pkgs.terraform-providers.mkProvider {
    owner = "terraform-providers";
    provider-source-address = "registry.terraform.io/hashicorp/consul";
    repo = "terraform-provider-consul";
    rev = "v2.11.0";
    sha256 = "sha256-LfR5E+xDEMxse1zQPCZvsa/PBJWIkxJHewA6/ek6+wA=";
    vendorSha256 = null;
    version = "2.11.0";
  };
  rundeck = pkgs.terraform-providers.mkProvider {
    owner = "rundeck";
    provider-source-address = "registry.terraform.io/hashicorp/rundeck";
    repo = "terraform-provider-rundeck";
    rev = "v0.4.0";
    sha256 = "sha256-+eanESS4UhFj/C2lMYfXfjDKx6BR8OM8QRx5q2ULI/Q=";
    vendorSha256 = null;
    version = "0.4.0";
  };
  grafana = pkgs.terraform-providers.mkProvider {
    owner = "grafana";
    provider-source-address = "registry.terraform.io/hashicorp/grafana";
    repo = "terraform-provider-grafana";
    rev = "v1.9.0";
    sha256 = "sha256-1yYrhlU9MBeVr8eC3d+T8ruiSagVSM/gBSYlm5zX26Y=";
    vendorSha256 = null;
    version = "1.9.0";
  };
  terraform_0_13 = pkgs.terraform_0_13;
  terraform_with_plugins = terraform_0_13.withPlugins (p: [
    aws
    consul
    # p.template archived
    rundeck
    grafana
    p.null
  ]);
  shell = pkgs.mkShell {
    inherit terraform_0_13 aws;
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

