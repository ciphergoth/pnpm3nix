{ pkgs ? import <nixpkgs> {}, tarjanSrc ? /Users/paul/g/zerbongle/tarjan }:

let
  # Pin to specific git commit for reproducibility
  pinnedSrc = builtins.fetchGit {
    url = tarjanSrc;
    rev = "f27f8bf4213467746877e44f1ed15fba720e2bff";
  };
in

pkgs.rustPlatform.buildRustPackage {
  pname = "tarjan-cli";
  version = "0.1.0-f27f8bf";

  src = pinnedSrc;

  cargoLock = {
    lockFile = pinnedSrc + "/Cargo.lock";
  };

  meta = {
    description = "CLI tool for finding strongly connected components using Tarjan's algorithm";
  };
}
