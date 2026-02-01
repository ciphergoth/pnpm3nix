{ pkgs ? import <nixpkgs> {} }:

let
  pinnedSrc = builtins.fetchGit {
    url = "https://github.com/ciphergoth/tarjan-cli.git";
    rev = "9957acc802de54b1c618e787d1a3a5c02efe4d9c";
  };
in

pkgs.rustPlatform.buildRustPackage {
  pname = "tarjan-cli";
  version = "0.1.0-9957acc";

  src = pinnedSrc;

  cargoLock = {
    lockFile = pinnedSrc + "/Cargo.lock";
  };

  meta = {
    description = "CLI tool for finding strongly connected components using Tarjan's algorithm";
  };
}
