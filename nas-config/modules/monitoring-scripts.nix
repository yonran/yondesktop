{ config, lib, pkgs, ... }:

{
  # Make the bpftrace scripts executable in system packages
  environment.systemPackages = [
    (pkgs.runCommand "monitoring-scripts" {
      buildInputs = [ pkgs.makeWrapper ];
    } ''
      mkdir -p $out/bin
      cp ${../scripts/zfs_file_writers.bt} $out/bin/zfs_file_writers
      chmod +x $out/bin/zfs_file_writers
      
      # Fix shebang to point to the correct bpftrace binary
      substituteInPlace $out/bin/zfs_file_writers \
        --replace "#!/usr/bin/env bpftrace" "#!${pkgs.bpftrace}/bin/bpftrace"
    '')
  ];
}