{
  pkgs ? import <nixpkgs> {}
, fetchFromGitHub ? pkgs.fetchFromGitHub
, buildGoPackage ? pkgs.buildGoPackage
, lib ? pkgs.lib
, callPackage ? lib.callPackage
}:
let oldnix = pkgs.fetchFromGitHub {
  owner = "nixos";
  repo = "nixpkgs";
  rev = "c38fae0a2c9b4f53d160333f6331cc51c473f3a3";
  sha256 = "oUXX926yH5maZtvT2MBe6KNNpxBIWgRu0jZW3cSUG78=";
};
packer_0_8_depsBeforeIn = builtins.elemAt (builtins.match "([[:print:]\n]+)[[:space:]]+in[[:space:]]+[[:print:]\n]+" (builtins.readFile "${oldnix}/pkgs/development/tools/packer/deps.nix")) 0;
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
{
  packer_0_8 = buildGoPackage rec {
    name = "packer";
    pname = "packer";
    goPackagePath = "github.com/mitchellh/packer";
    # copied from deps.nix
    src = fetchFromGitHub {
      owner = "mitchellh";
      repo = "packer";
      rev = "f8f7b7a34c1be06058f5aca23a51247db12cdbc5";
      sha256 = "162ja4klyb3nv44rhdg2gd3xrr4n0l0gi49cn1mr1s2h9yznphyp";
    };

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
}
