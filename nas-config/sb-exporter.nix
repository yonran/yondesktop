{ lib
, python3
, fetchFromGitHub
, makeWrapper
, stdenvNoCC
}:

# The upstream project migrated from poetry to uv and no longer ships a
# build-system or an entry point; app/main.py is just run directly with app/ on
# sys.path (which happens automatically -- sys.path[0] is the script's dir). So
# rather than buildPythonApplication we build a python env with the deps and wrap
# `python app/main.py`.
#
# nixpkgs 26.05 already provides new-enough deps (prometheus-client >=0.22,
# structlog >=25.4, aiohttp >=3.12, beautifulsoup4 >=4.13, python 3.13), so no
# version overrides are needed anymore.
let
  pythonEnv = python3.withPackages (ps: with ps; [
    aiohttp
    prometheus-client
    structlog
    beautifulsoup4
  ]);
in
stdenvNoCC.mkDerivation {
  pname = "sb-exporter";
  version = "0.1.0-unstable-2026-07-05";

  src = fetchFromGitHub {
    owner = "yonran";
    repo = "sb8200_prometheus_exporter";
    # branch: fix/outage-resilience-and-login-retry
    rev = "99404d61f287dd7acdaf88bbfb9c048b645b58ad";
    hash = "sha256-/AQnVjx+tJMr3A5HeKa3HtivERkY0tZv6W3O0txwBU8=";
  };

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/libexec/sb-exporter
    cp -r app $out/libexec/sb-exporter/app
    # ExecStart in sb-exporter-service.nix runs $out/bin/main.py
    makeWrapper ${pythonEnv}/bin/python $out/bin/main.py \
      --add-flags $out/libexec/sb-exporter/app/main.py
    runHook postInstall
  '';

  meta = {
    description = "Prometheus exporter for the Arris SB8200 cable modem";
    homepage = "https://github.com/yonran/sb8200_prometheus_exporter";
    mainProgram = "main.py";
  };
}
