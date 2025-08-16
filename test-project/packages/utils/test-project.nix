{ pkgs ? import <nixpkgs> {} }:

let
  overlay = import ../../../overlay.nix;
  pkgsWithOverlay = pkgs.extend overlay;
in
pkgsWithOverlay.mkPnpmPackage {
  workspace = ../..;
  components = ["packages/utils"];
  script = "";
}
