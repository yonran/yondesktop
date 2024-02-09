{
  pkgs ? import <nixpkgs> {}
, fetchFromGitHub ? pkgs.fetchFromGitHub
, buildGoPackage ? pkgs.buildGoPackage
, buildGoModule ? pkgs.buildGoModule
, lib ? pkgs.lib
, callPackage ? lib.callPackage
}:
let oldnix = pkgs.fetchFromGitHub {
  owner = "nixos";
  repo = "nixpkgs";
  rev = "c38fae0a2c9b4f53d160333f6331cc51c473f3a3";
  sha256 = "oUXX926yH5maZtvT2MBe6KNNpxBIWgRu0jZW3cSUG78=";
};
oldnix_packer_1_3_1 = pkgs.fetchFromGitHub {
  owner = "nixos";
  repo = "nixpkgs";
  rev = "11f1b22b4b5bb01ff25b3d64bd780c39ce1353cf";
  sha256 = "sha256-vhgKYtLDwi2TsfdO9KFPXGY1jQbP/ug7aS3g/aucsG0=";
};
oldnix_packer_1_4_1 = pkgs.fetchFromGitHub {
  owner = "nixos";
  repo = "nixpkgs";
  rev = "a7a904768cc163376604c1743c97664f9931fa54";
  sha256 = "sha256-yXO0IoczWna1wDoGGFLLB1DI0hZqmwDNXW7Ssipr6u8=";
};
oldnix_packer_1_5_0 = pkgs.fetchFromGitHub {
  owner = "nixos";
  repo = "nixpkgs";
  rev = "b8afcb742a77de06c3306ec8e5e51b3176630b0f";
  sha256 = "sha256-j01dJz++z/fHNYVQkoCt4MqO90QmpK5aDfNnn0ni300=";
};
oldnix_packer_1_6_6 = pkgs.fetchFromGitHub {
  owner = "nixos";
  repo = "nixpkgs";
  rev = "b3fce6596dfca030188821f15f54e386a208858f";
  sha256 = "sha256-a58hPAQmAxA2IP6U7+Ugpj0/fYJqA0hlBfLOKfTJwvE=";
};
oldnix_packer_1_7_10 = pkgs.fetchFromGitHub {
  owner = "nixos";
  repo = "nixpkgs";
  rev = "49268792710c34633fcfbd261b746cfe9af1576b";
  sha256 = "sha256-F5l08VJ7ES3TEmqtwePEvlaonk/+Oz79Q87PZT1hfkI=";
};
oldnix_packer_1_8_4 = pkgs.fetchFromGitHub {
  owner = "nixos";
  repo = "nixpkgs";
  rev = "0922d4127e4ae165b127a6d1c599c94aa68707ba";
  sha256 = "sha256-FKIYcS7i/icyzc3oqSyMbpet6JCDq3uoqsx0CwOUwx8=";
};
# hack for error: The requested URL returned error: 404
# since github.com/go-fsnotify/fsnotify moved to github.com/fsnotify/fsnotify
fixupFsNotifyFetchFromGitHub = fetchFromGitHub: {owner, repo, ...} @ args:
  let fixedArgs = if [owner repo] == ["go-fsnotify" "fsnotify"] then {owner = "fsnotify";} else {};
  in fetchFromGitHub (args // fixedArgs);
# don't mkDerivation; just return the deps array
packer_0_8_depsPassThrough = import ./packer_0_8_deps.nix {
  fetchFromGitHub = fixupFsNotifyFetchFromGitHub ({owner, repo, rev, sha256}: {
    url = "https://github.com/${owner}/${repo}";
    inherit rev sha256;
  });
  fetchgit = lib.trivial.id;
  stdenv = null;
  lib = null;
  fetchhg = null;
  fetchbzr = null;
};
# converts old-format deps.nix array
# e.g. https://github.com/NixOS/nixpkgs/blob/c38fae0a2c9b4f53d160333f6331cc51c473f3a3/pkgs/development/tools/packer/deps.nix
# to new-format deps structure
# e.g. https://github.com/NixOS/nixpkgs/blob/6979a72840a1f6f034cb6a11a3d114b17f792ad4/pkgs/tools/admin/aws-env/deps.nix
convertDep = {root, src}:
  {
    goPackagePath = root;
    fetch = {
      type = "git";
    } // src;
  };
convertDeps = old: builtins.map convertDep old;

packer_0_8_depsNewFormat = convertDeps packer_0_8_depsPassThrough;
packer_0_8_base = pkgs.callPackage "${oldnix}/pkgs/development/tools/packer/default.nix" {
  # fix for error: attribute 'lib' missing
  stdenv = pkgs.stdenv // {lib = pkgs.lib;};
  # hack for error: The requested URL returned error: 404
  # since github.com/go-fsnotify/fsnotify moved to github.com/fsnotify/fsnotify
  fetchFromGitHub = {owner, repo, ...} @ args:
    let fixedArgs = if [owner repo] == ["go-fsnotify" "fsnotify"] then {owner = "fsnotify";} else {};
    in fetchFromGitHub (args // fixedArgs);
};
in
rec {
  packer_0_8 = buildGoPackage rec {
    name = "packer";
    pname = "packer";
    goPackagePath = "github.com/mitchellh/packer";
    # copied from deps.nix
    # src = fetchFromGitHub {
    #   owner = "mitchellh";
    #   repo = "packer";
    #   rev = "f8f7b7a34c1be06058f5aca23a51247db12cdbc5";
    #   sha256 = "162ja4klyb3nv44rhdg2gd3xrr4n0l0gi49cn1mr1s2h9yznphyp";
    # };
    src = ~/third-party/golang/packer;

    # extraSrcs is an alternative to goDeps (which can only be assigned a path)
    # extraSrcs = packer_0_8_depsNewFormat;
    extraSrcs = builtins.map ({root, src}: {
      goPackagePath = root;
      inherit src;
    }) (callPackage ./packer_0_8_deps.nix {
      fetchFromGitHub = fixupFsNotifyFetchFromGitHub fetchFromGitHub;
    });

    postFixup = ''
    # prefix all plugins except packer with packer-
    # like the gox -output invocation used by packer's Makefile
    for x in $out/bin/*; do
      DIR=$(dirname $x)
      FILENAME=$(basename $x)
      if [ "$FILENAME" != packer ]; then
        mv $x $DIR/packer-$FILENAME
      fi
    done
    '';
  };
  packer_1_3_1 = callPackage "${oldnix_packer_1_3_1}/pkgs/development/tools/packer/default.nix" {
    stdenv = pkgs.stdenv // {lib = pkgs.lib;};
  };
  # can't build on mac 2023
  # does not build with bad sys
  packer_1_4_1 = callPackage "${oldnix_packer_1_4_1}/pkgs/development/tools/packer/default.nix" {
    stdenv = pkgs.stdenv // {lib = pkgs.lib;};
  };
  # can't build on mac 2023
  packer_1_5_0 = callPackage "${oldnix_packer_1_5_0}/pkgs/development/tools/packer/default.nix" {
    stdenv = pkgs.stdenv // {lib = pkgs.lib;};
  };
  # can't build on mac 2023
  packer_1_6_6 = callPackage "${oldnix_packer_1_6_6}/pkgs/development/tools/packer/default.nix" {
    # stdenv = pkgs.stdenv // {lib = pkgs.lib;};
  };
  # can't ssh 2023
  packer_1_7_10 = callPackage "${oldnix_packer_1_7_10}/pkgs/development/tools/packer/default.nix" {};

  packer_1_8_4 = callPackage "${oldnix_packer_1_8_4}/pkgs/development/tools/packer/default.nix" {};
  # can't ssh 2023
  packer_1_8_7 = buildGoModule rec {
    pname = "packer";
    version = "1.8.7";
    src = fetchFromGitHub {
      owner = "hashicorp";
      repo = "packer";
      rev = "v${version}";
      sha256 = "sha256-M37JFKAv1GMtMr0UQ8lFEcTuboSMmCQ29dr6OP07HB8=";
    };
    subPackages = [ "." ];
    vendorHash = "sha256-uQQv89562bPOoKDu5qEEs+p+N8HPRmgFZKUc5YEsz/w=";
  };

  packer_1_9_1 = buildGoModule rec {
    pname = "packer";
    version = "1.9.1";
    src = fetchFromGitHub {
      owner = "hashicorp";
      repo = "packer";
      rev = "v${version}";
      hash = "sha256-imdVXgW3w0Bv4qWPJIRhZPim7c0WRHKvRS/uBk7nzaI=";
    };
    subPackages = [ "." ];
    vendorHash = "sha256-aRjSYnb8xyjI4Gn4I91aP3evCqimlL5zR6jpgWNFRME=";
      # plugins = [
        amazon = buildGoModule rec {
          pname = "packer-plugin-amazon";
          version = "1.2.6";
          src = fetchFromGitHub {
            owner = "hashicorp";
            repo = "packer-plugin-amazon";
            rev = "v${version}";
            hash = "sha256-ayjEpGm4KHr6Qs6I4RHlbCTna+5TFqq7oEnAR0DyrvE=";
          };
          vendorHash = "sha256-zOrV5PLULWBT7NaireOh0TqBVjKmal1MQb+drqnZUzw=";
        };
        chef = buildGoModule rec {
          pname = "packer-plugin-chef";
          version = "1.0.2";
          src = fetchFromGitHub {
            owner = "hashicorp";
            repo = "packer-plugin-chef";
            rev = "v${version}";
            hash = "sha256-YZulUoet6GHLQ4Zlf4DGkS9e9SdB1g3Ua/KQRCcQgYg=";
          };
          vendorHash = "sha256-CQDfUi3wBEh7D7bawmEmRRpKCPXdFpneaIcLwMcZGOY=";
        };
        
      # ];
    passthru = {
    };
    postFixup = ''
    for providerDir in ${toString [amazon chef]}; do
      for plugin in $providerDir/bin/*; do
        ln -s $plugin $out/bin/
      done
    done
    '';

  };
  packer = packer_1_9_1;
}
