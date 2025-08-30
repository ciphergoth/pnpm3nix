{ pkgs ? import <nixpkgs> {}, tarjanSrc ? /Users/paul/g/zerbongle/tarjan }:

pkgs.rustPlatform.buildRustPackage {
  pname = "tarjan-cli";
  version = "0.1.0";
  
  src = tarjanSrc;
  
  cargoLock = {
    lockFile = tarjanSrc + "/Cargo.lock";
  };
  
  meta = {
    description = "CLI tool for finding strongly connected components using Tarjan's algorithm";
  };
}