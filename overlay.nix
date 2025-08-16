final: prev: {
  inherit ((import ./pnpm2nix.nix { pkgs = final; })) mkPnpmPackage;
}