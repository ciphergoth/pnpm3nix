final: prev: {
  inherit ((import ./pnpm2nix-scc.nix { 
    pkgs = final;
  })) mkPnpmPackage;
}