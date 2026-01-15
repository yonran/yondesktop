#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

rsync -r --delete --rsync-path='sudo rsync' --exclude=hardware-configuration.nix "$SCRIPT_DIR/" yonran@home.yonathan.org:/etc/nixos/

ssh yonran@home.yonathan.org -- sudo nixos-rebuild switch
