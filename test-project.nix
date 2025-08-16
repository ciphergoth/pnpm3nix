{ pkgs ? import <nixpkgs> {} }:

let
  pnpm2nix = import ./pnpm2nix.nix { inherit pkgs; };
in
pnpm2nix.mkPnpmPackage {
  src = ./test-project;
}