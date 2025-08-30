{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = [ 
    pkgs.nodejs
    pkgs.nodePackages.pnpm
    pkgs.yaml2json
    pkgs.jq
  ];
}