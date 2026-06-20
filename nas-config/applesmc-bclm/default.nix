# Out-of-tree build of the patched Apple SMC kernel module.
#
# Build with the running system's kernel, e.g. on the box:
#   nix-build -E 'let s = import <nixpkgs/nixos> {}; \
#     in s.config.boot.kernelPackages.callPackage ./default.nix {}'
#
# Or wire it into configuration.nix:
#   boot.extraModulePackages = [
#     (config.boot.kernelPackages.callPackage ./applesmc-bclm {})
#   ];
# (see README.md for the in-tree-module shadowing caveat before enabling that).
{ lib, stdenv, kernel }:

stdenv.mkDerivation {
  pname = "applesmc-bclm";
  version = "0.1.0-${kernel.modDirVersion}";

  src = ./.;

  nativeBuildInputs = kernel.moduleBuildDependencies;

  # Build via the Makefile's `all` target (recurses into KDIR). We intentionally do
  # NOT pass kernel.makeFlags here: those are for building the kernel itself and break
  # an out-of-tree module build (e.g. --eval=undefine / O=$(buildRoot)).
  makeFlags = [
    "KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
  ];

  installPhase = ''
    runHook preInstall
    install -D applesmc.ko "$out/lib/modules/${kernel.modDirVersion}/misc/applesmc.ko"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Apple SMC driver patched to expose battery charge_control_end_threshold (BCLM)";
    license = licenses.gpl2Only;
    platforms = [ "x86_64-linux" ];
  };
}
