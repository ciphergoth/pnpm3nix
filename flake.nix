{
  description = "pnpm2nix with SCC-based cycle-aware derivations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    {
      overlays.default = final: prev: {
        inherit ((import ./pnpm2nix.nix { pkgs = final; })) mkPnpmPackage;
      };
    } // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        pnpm2nix = import ./pnpm2nix.nix { inherit pkgs; };
      in
      {
        packages.default = pnpm2nix.mkPnpmPackage;
      }
    );
}
