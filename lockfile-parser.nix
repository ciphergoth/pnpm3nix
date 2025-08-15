{ pkgs ? import <nixpkgs> {} }:

let
  # Convert the pnpm lockfile to JSON using yaml2json
  lockfileJsonFile = pkgs.runCommand "lockfile.json" {
    nativeBuildInputs = [ pkgs.yaml2json ];
  } ''
    yaml2json < ${./test-project/pnpm-lock.yaml} > $out
  '';

  # Create a derivation that parses the JSON and extracts package info
  parsedLockfile = pkgs.runCommand "parsed-lockfile" {
    nativeBuildInputs = [ pkgs.jq ];
  } ''
    # Parse the JSON and extract packages section
    cat ${lockfileJsonFile} | jq '.packages' > $out
  '';

in {
  inherit lockfileJsonFile parsedLockfile;
}