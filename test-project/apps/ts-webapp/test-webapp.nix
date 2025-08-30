{ pkgs ? import <nixpkgs> {} }:

let
  overlay = import ../../../overlay.nix;
  pkgsWithOverlay = pkgs.extend overlay;
in
pkgsWithOverlay.mkPnpmPackage {
  workspace = ../..;
  component = "apps/ts-webapp";
  script = "build";
}