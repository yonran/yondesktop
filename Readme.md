# Nix setup for laptop

## Nix-shell scripts

These scripts currently depend on `<nixpkgs>`.
It works with nix-channel set to https://channels.nixos.org/nixpkgs-21.11-darwin

[`nix-shell node16.nix`](./node16.nix) creates a shell with nodejs16 and npm installed.
Then `npm install` your node dependencies (to `node_modules`)

[`nix-shell python3.nix`](./python3.nix) creates a shell with python and pip installed.
Then `pip install` your python dependencies (to `env`).

[`nix-shell terraform1.1.nix`](./terraform1.1.nix) creates a shell with terraform installed.
Then terraform init to download all the providers (to `.terraform`).
