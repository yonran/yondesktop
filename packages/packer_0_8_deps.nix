# copied from https://github.com/NixOS/nixpkgs/blob/c38fae0a2c9b4f53d160333f6331cc51c473f3a3/pkgs/development/tools/packer/deps.nix
# except to return the whole goDeps array instead of returning a single derivation
# This file was generated by go2nix.
{ stdenv, lib, fetchFromGitHub, fetchgit, fetchhg, fetchbzr }:

let
  goDeps = [
    {
      root = "github.com/mitchellh/packer";
      src = fetchFromGitHub {
        owner = "mitchellh";
        repo = "packer";
        rev = "f8f7b7a34c1be06058f5aca23a51247db12cdbc5";
        sha256 = "162ja4klyb3nv44rhdg2gd3xrr4n0l0gi49cn1mr1s2h9yznphyp";
      };
    }
    {
      root = "github.com/mitchellh/gox";
      src = fetchFromGitHub {
        owner = "mitchellh";
        repo = "gox";
        rev = "ef1967b9f538fe467e6a82fc42ec5dff966ad4ea";
        sha256 = "0i9s8fp6m2igx93ffv3rf5v5hz7cwrx7pbxrz4cg94hba3sy3nfj";
      };
    }
    {
      root = "github.com/mitchellh/iochan";
      src = fetchFromGitHub {
        owner = "mitchellh";
        repo = "iochan";
        rev = "87b45ffd0e9581375c491fef3d32130bb15c5bd7";
        sha256 = "1435kdcx3j1xgr6mm5c7w7hjx015jb20yfqlkp93q143hspf02fx";
      };
    }
    {
      root = "github.com/hashicorp/atlas-go";
      src = fetchFromGitHub {
        owner = "hashicorp";
        repo = "atlas-go";
        rev = "d1d08e8e25f0659388ede7bb8157aaa4895f5347";
        sha256 = "0bbqh94i8qllp51ln1mmcjy5srny7s4xg0l353kccvk3c7s68m03";
      };
    }
    {
      root = "github.com/hashicorp/go-checkpoint";
      src = fetchFromGitHub {
        owner = "hashicorp";
        repo = "go-checkpoint";
        rev = "88326f6851319068e7b34981032128c0b1a6524d";
        sha256 = "1npasn9lmvx57nw3wkswwvl5k0wmn01jpalbwv832x5wq4r0nsz4";
      };
    }
    {
      root = "github.com/hashicorp/go-msgpack";
      src = fetchFromGitHub {
        owner = "hashicorp";
        repo = "go-msgpack";
        rev = "fa3f63826f7c23912c15263591e65d54d080b458";
        sha256 = "1f6rd6bm2dm2rk46x8cqrxh5nks1gpk6dvvsag7s5pdjgdxy951k";
      };
    }
    {
      root = "github.com/hashicorp/go-multierror";
      src = fetchFromGitHub {
        owner = "hashicorp";
        repo = "go-multierror";
        rev = "56912fb08d85084aa318edcf2bba735b97cf35c5";
        sha256 = "0s01cqdab2f7fxkkjjk2wqx05a1shnwlvfn45h2pi3i4gapvcn0r";
      };
    }
    {
      root = "github.com/hashicorp/go-version";
      src = fetchFromGitHub {
        owner = "hashicorp";
        repo = "go-version";
        rev = "999359b6b7a041ce16e695d51e92145b83f01087";
        sha256 = "0z2bzphrdkaxh5vnvjh3g25d6cykchshwwbyqgji91mpgjd30pbm";
      };
    }
    {
      root = "github.com/hashicorp/yamux";
      src = fetchFromGitHub {
        owner = "hashicorp";
        repo = "yamux";
        rev = "ae139c4ae7fe21e9d99459d2acc57967cebb6918";
        sha256 = "1p5h2wklj8lb1vnjnd5kw7cshfmiw7jmzw9radln955hzd5xzbnl";
      };
    }
    {
      root = "github.com/mitchellh/cli";
      src = fetchFromGitHub {
        owner = "mitchellh";
        repo = "cli";
        rev = "8102d0ed5ea2709ade1243798785888175f6e415";
        sha256 = "08mj1l94pww72jy34gk9a483hpic0rrackskfw13r3ycy997w7m2";
      };
    }
    {
      root = "github.com/mitchellh/mapstructure";
      src = fetchFromGitHub {
        owner = "mitchellh";
        repo = "mapstructure";
        rev = "281073eb9eb092240d33ef253c404f1cca550309";
        sha256 = "1zjx9fv29639sp1fn84rxs830z7gp7bs38yd5y1hl5adb8s5x1mh";
      };
    }
    {
      root = "github.com/mitchellh/osext";
      src = fetchFromGitHub {
        owner = "mitchellh";
        repo = "osext";
        rev = "0dd3f918b21bec95ace9dc86c7e70266cfc5c702";
        sha256 = "02pczqml6p1mnfdrygm3rs02g0r65qx8v1bi3x24dx8wv9dr5y23";
      };
    }
    {
      root = "github.com/mitchellh/panicwrap";
      src = fetchFromGitHub {
        owner = "mitchellh";
        repo = "panicwrap";
        rev = "45cbfd3bae250c7676c077fb275be1a2968e066a";
        sha256 = "0mbha0nz6zcgp2pny2x03chq1igf9ylpz55xxq8z8g2jl6cxaghn";
      };
    }
    {
      root = "github.com/mitchellh/prefixedio";
      src = fetchFromGitHub {
        owner = "mitchellh";
        repo = "prefixedio";
        rev = "89d9b535996bf0a185f85b59578f2e245f9e1724";
        sha256 = "0lc64rlizb412msd32am2fixkh0536pjv7czvgyw5fskn9kgk3y2";
      };
    }
    {
      root = "github.com/mitchellh/reflectwalk";
      src = fetchFromGitHub {
        owner = "mitchellh";
        repo = "reflectwalk";
        rev = "eecf4c70c626c7cfbb95c90195bc34d386c74ac6";
        sha256 = "1nm2ig7gwlmf04w7dbqd8d7p64z2030fnnfbgnd56nmd7dz8gpxq";
      };
    }
    {
      root = "github.com/mitchellh/go-fs";
      src = fetchFromGitHub {
        owner = "mitchellh";
        repo = "go-fs";
        rev = "a34c1b9334e86165685a9449b782f20465eb8c69";
        sha256 = "11sy85p77ffmavpiichzybrfvjm1ilsi4clx98n3363arksavs5i";
      };
    }
    {
      root = "github.com/mitchellh/goamz";
      src = fetchFromGitHub {
        owner = "mitchellh";
        repo = "goamz";
        rev = "caaaea8b30ee15616494ee68abd5d8ebbbef05cf";
        sha256 = "0bshq69ir9h2nszbr74yvcg5wnd9a5skfmr9bgk014k9wwk7dc72";
      };
    }
    {
      root = "github.com/mitchellh/multistep";
      src = fetchFromGitHub {
        owner = "mitchellh";
        repo = "multistep";
        rev = "162146fc57112954184d90266f4733e900ed05a5";
        sha256 = "0ydhbxziy9204qr43pjdh88y2jg34g2mhzdapjyfpf8a1rin6dn3";
      };
    }
    {
      root = "github.com/ActiveState/tail";
      src = fetchFromGitHub {
        owner = "ActiveState";
        repo = "tail";
        rev = "4b368d1590196ade29993d6a0896591403180bbd";
        sha256 = "183y44skn75lkpsjd3zlbx8vc3b930p3nkpc1ybq3k50s4bzhsll";
      };
    }
    {
      root = "google.golang.org/api";
      src = fetchgit {
        url = "https://github.com/google/google-api-go-client.git";
        rev = "a5c3e2a4792aff40e59840d9ecdff0542a202a80";
        sha256 = "1kigddnbyrl9ddpj5rs8njvf1ck54ipi4q1282k0d6b3am5qfbj8";
      };
    }
    {
      root = "golang.org/x/crypto";
      src = fetchgit {
        url = "https://go.googlesource.com/crypto.git";
        rev = "81bf7719a6b7ce9b665598222362b50122dfc13b";
        sha256 = "0rwzc2ls842d0g588b5xik59srwzawch3nb1dlcqwm4a1132mvmr";
      };
    }
    {
      root = "golang.org/x/oauth2";
      src = fetchgit {
        url = "https://go.googlesource.com/oauth2.git";
        rev = "397fe7649477ff2e8ced8fc0b2696f781e53745a";
        sha256 = "0fza0l7iwh6llkq2yzqn7dxi138vab0da64lnghfj1p71fprjzn8";
      };
    }
    {
      root = "golang.org/x/net";
      src = fetchgit {
        url = "https://go.googlesource.com/net.git";
        rev = "7654728e381988afd88e58cabfd6363a5ea91810";
        sha256 = "08i6kkzbckbc5k15bdlqkbird48zmc24qr505hlxlb11djjgdiml";
      };
    }
    {
      root = "google.golang.org/appengine";
      src = fetchgit {
        url = "https://github.com/golang/appengine.git";
        rev = "cdd515334b113fdc9b35cb1e7a3b457eeb5ad5cf";
        sha256 = "0l0rddpfbddbi8kizg2n25w7bdhf99f0iz7ghwz7fq6k4rmq44ws";
      };
    }
    {
      root = "google.golang.org/cloud";
      src = fetchgit {
        url = "https://github.com/GoogleCloudPlatform/gcloud-golang.git";
        rev = "e34a32f9b0ecbc0784865fb2d47f3818c09521d4";
        sha256 = "1rzac44kzhd7r6abdy5qyj69y64wy9r73vnxsdalfr5m0i55fqk4";
      };
    }
    {
      root = "github.com/golang/protobuf";
      src = fetchFromGitHub {
        owner = "golang";
        repo = "protobuf";
        rev = "59b73b37c1e45995477aae817e4a653c89a858db";
        sha256 = "1dx22jvhvj34ivpr7gw01fncg9yyx35mbpal4mpgnqka7ajmgjsa";
      };
    }
    {
      root = "github.com/mitchellh/gophercloud-fork-40444fb";
      src = fetchFromGitHub {
        owner = "mitchellh";
        repo = "gophercloud-fork-40444fb";
        rev = "40444fbc2b10960682b34e6822eb9179216e1ae1";
        sha256 = "06bm7hfi03c75npzy51wbl9qyln35c3kzj9yn2w4fhn0k9dia9s3";
      };
    }
    {
      root = "github.com/racker/perigee";
      src = fetchFromGitHub {
        owner = "racker";
        repo = "perigee";
        rev = "44a7879d89b7040bcdb51164a83292ef5bf9deec";
        sha256 = "04wscffagpbcfjs6br96n46aqy43cq6ndq16nlpvank0m98jaax0";
      };
    }
    {
      root = "github.com/going/toolkit";
      src = fetchFromGitHub {
        owner = "going";
        repo = "toolkit";
        rev = "5bff591dc40da25dcc875d3fa1a3373d74d45411";
        sha256 = "15gnlqignm7xcp2chrz7d7qqlibkbfrrsvbcysk8lrj9l7md8vjf";
      };
    }
    {
      root = "github.com/mitchellh/go-vnc";
      src = fetchFromGitHub {
        owner = "mitchellh";
        repo = "go-vnc";
        rev = "723ed9867aed0f3209a81151e52ddc61681f0b01";
        sha256 = "0nlya2rbmwb3jycqsyah1pn4386712mfrfiprprkbzcna9q7lp1h";
      };
    }
    {
      root = "github.com/howeyc/fsnotify";
      src = fetchFromGitHub {
        owner = "howeyc";
        repo = "fsnotify";
        rev = "4894fe7efedeeef21891033e1cce3b23b9af7ad2";
        sha256 = "09r3h200nbw8a4d3rn9wxxmgma2a8i6ssaplf3zbdc2ykizsq7mn";
      };
    }
    {
      root = "gopkg.in/tomb.v1";
      src = fetchgit {
        url = "https://gopkg.in/tomb.v1.git";
        rev = "dd632973f1e7218eb1089048e0798ec9ae7dceb8";
        sha256 = "1lqmq1ag7s4b3gc3ddvr792c5xb5k6sfn0cchr3i2s7f1c231zjv";
      };
    }
    {
      root = "github.com/vaughan0/go-ini";
      src = fetchFromGitHub {
        owner = "vaughan0";
        repo = "go-ini";
        rev = "a98ad7ee00ec53921f08832bc06ecf7fd600e6a1";
        sha256 = "1l1isi3czis009d9k5awsj4xdxgbxn4n9yqjc1ac7f724x6jacfa";
      };
    }
    {
      root = "github.com/aws/aws-sdk-go";
      src = fetchFromGitHub {
        owner = "aws";
        repo = "aws-sdk-go";
        rev = "f096b7d61df3d7d6d97f0e701f92616d1ea5420d";
        sha256 = "0z2fknqxdyb5vw4am46cn60m15p9fjsqzpzaj2pamp436l0cpjkw";
      };
    }
    {
      root = "github.com/digitalocean/godo";
      src = fetchFromGitHub {
        owner = "digitalocean";
        repo = "godo";
        rev = "2a0d64a42bb60a95677748a4d5729af6184330b4";
        sha256 = "0854577b08fw9bjflk044ph16p15agxhh6xbzn71rhfvxg5yg5mi";
      };
    }
    {
      root = "github.com/dylanmei/winrmtest";
      src = fetchFromGitHub {
        owner = "dylanmei";
        repo = "winrmtest";
        rev = "025617847eb2cf9bd1d851bc3b22ed28e6245ce5";
        sha256 = "1i0wq6r1vm3nhnia3ycm5l590gyia7cwh6971ppnn4rrdmvsw2qh";
      };
    }
    {
      root = "github.com/klauspost/pgzip";
      src = fetchFromGitHub {
        owner = "klauspost";
        repo = "pgzip";
        rev = "47f36e165cecae5382ecf1ec28ebf7d4679e307d";
        sha256 = "1bfka02xrhp4fg9pz2v4ppxa46b59bwy5n88c7hbbxqxm8z30yca";
      };
    }
    {
      root = "github.com/masterzen/winrm";
      src = fetchFromGitHub {
        owner = "masterzen";
        repo = "winrm";
        rev = "54ea5d01478cfc2afccec1504bd0dfcd8c260cfa";
        sha256 = "0qzdmsjgcf5n0jzjf4gd22lhqwn9yagynk1izjz3978gr025p2zm";
      };
    }
    {
      root = "github.com/google/go-querystring";
      src = fetchFromGitHub {
        owner = "google";
        repo = "go-querystring";
        rev = "2a60fc2ba6c19de80291203597d752e9ba58e4c0";
        sha256 = "0raf6r3dd8rxxppzrbhp1y6k5csgfkfs7b0jylj65sbg0hbzxvbr";
      };
    }
    {
      root = "github.com/go-ini/ini";
      src = fetchFromGitHub {
        owner = "go-ini";
        repo = "ini";
        rev = "afbd495e5aaea13597b5e14fe514ddeaa4d76fc3";
        sha256 = "0xi8zr9qw38sdbv95c2ip31yczbm4axdvmj3ljyivn9xh2nbxfia";
      };
    }
    {
      root = "github.com/klauspost/compress";
      src = fetchFromGitHub {
        owner = "klauspost";
        repo = "compress";
        rev = "112706bf3743c241303219f9c5ce2e6635f69221";
        sha256 = "1gyf5hf8wivbx6s99x2rxq2a335b49av2xb43nikgbzm4qn7win7";
      };
    }
    {
      root = "github.com/masterzen/simplexml";
      src = fetchFromGitHub {
        owner = "masterzen";
        repo = "simplexml";
        rev = "95ba30457eb1121fa27753627c774c7cd4e90083";
        sha256 = "0pwsis1f5n4is0nmn6dnggymj32mldhbvihv8ikn3nglgxclz4kz";
      };
    }
    {
      root = "github.com/masterzen/xmlpath";
      src = fetchFromGitHub {
        owner = "masterzen";
        repo = "xmlpath";
        rev = "13f4951698adc0fa9c1dda3e275d489a24201161";
        sha256 = "1y81h7ymk3dp3w3a2iy6qd1dkm323rkxa27dzxw8vwy888j5z8bk";
      };
    }
    {
      root = "github.com/jmespath/go-jmespath";
      src = fetchFromGitHub {
        owner = "jmespath";
        repo = "go-jmespath";
        rev = "c01cf91b011868172fdcd9f41838e80c9d716264";
        sha256 = "0gfrqwl648qngp77g8m1g9g7difggq2cac4ydjw9bpx4bd7mw1rw";
      };
    }
    {
      root = "github.com/klauspost/cpuid";
      src = fetchFromGitHub {
        owner = "klauspost";
        repo = "cpuid";
        rev = "349c675778172472f5e8f3a3e0fe187e302e5a10";
        sha256 = "1s8baj42k66ny77qkm3n06kwayk4srwf4b9ss42612f3h86ka5i2";
      };
    }
    {
      root = "github.com/nu7hatch/gouuid";
      src = fetchFromGitHub {
        owner = "nu7hatch";
        repo = "gouuid";
        rev = "179d4d0c4d8d407a32af483c2354df1d2c91e6c3";
        sha256 = "1isyfix5w1wm26y3a15ha3nnpsxqaxz5ngq06hnh6c6y0inl2fwj";
      };
    }
    {
      root = "github.com/klauspost/crc32";
      src = fetchFromGitHub {
        owner = "klauspost";
        repo = "crc32";
        rev = "999f3125931f6557b991b2f8472172bdfa578d38";
        sha256 = "00ws3hrszxdnyj0cjk9b8b44xc8x5hizm0h22x6m3bb4c5b487wv";
      };
    }
    {
      root = "github.com/pierrec/lz4";
      src = fetchFromGitHub {
        owner = "pierrec";
        repo = "lz4";
        rev = "383c0d87b5dd7c090d3cddefe6ff0c2ffbb88470";
        sha256 = "0l23bmzqfvgh61zlikj6iakg0kz7lybs8zf0nscylskl2hlr09rp";
      };
    }
    {
      root = "github.com/packer-community/winrmcp";
      src = fetchFromGitHub {
        owner = "packer-community";
        repo = "winrmcp";
        rev = "3d184cea22ee1c41ec1697e0d830ff0c78f7ea97";
        sha256 = "0g2rwwhykm1z099gwkg1nmb1ggnizqlm2pbmy3qsdvjnl5246ca4";
      };
    }
    {
      root = "github.com/dylanmei/iso8601";
      src = fetchFromGitHub {
        owner = "dylanmei";
        repo = "iso8601";
        rev = "2075bf119b58e5576c6ed9f867b8f3d17f2e54d4";
        sha256 = "0px5aq4w96yyjii586h3049xm7rvw5r8w7ph3axhyismrqddqgx1";
      };
    }
    {
      root = "github.com/pierrec/xxHash";
      src = fetchFromGitHub {
        owner = "pierrec";
        repo = "xxHash";
        rev = "5a004441f897722c627870a981d02b29924215fa";
        sha256 = "146ibrgvgh61jhbbv9wks0mabkci3s0m68sg6shmlv1yixkw6gja";
      };
    }
    {
      root = "github.com/satori/go.uuid";
      src = fetchFromGitHub {
        owner = "satori";
        repo = "go.uuid";
        rev = "d41af8bb6a7704f00bc3b7cba9355ae6a5a80048";
        sha256 = "0lw8k39s7hab737rn4nngpbsganrniiv7px6g41l6f6vci1skyn2";
      };
    }
    {
      root = "github.com/rackspace/gophercloud";
      src = fetchFromGitHub {
        owner = "rackspace";
        repo = "gophercloud";
        rev = "680aa02616313d8399abc91f17a444cf9292f0e1";
        sha256 = "0pxzvhh6l1gfn31k6g8fz3x4b6mz88cx2rgpims0ys5cl212zrp1";
      };
    }
    {
      root = "gopkg.in/fsnotify.v0";
      src = fetchFromGitHub {
        owner = "go-fsnotify";
        repo = "fsnotify";
        rev = "ea925a0a47d225b2ca7f9932b01d2ed4f3ec74f6";
        sha256 = "15wqjpkfzsxnaxbz6y4r91hw6812g3sc4ipagxw1bya9klbnkdc9";
      };
    }
    {
      root = "github.com/tent/http-link-go";
      src = fetchFromGitHub {
        owner = "tent";
        repo = "http-link-go";
        rev = "ac974c61c2f990f4115b119354b5e0b47550e888";
        sha256 = "1fph21b6vp4cm73fkkykffggi57m656x9fd1k369fr6jbvq5fffj";
      };
    }
  ];

in

goDeps