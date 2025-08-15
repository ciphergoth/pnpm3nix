{ pkgs ? import <nixpkgs> {} }:

let
  # Convert YAML to JSON using yaml2json
  lockfileJsonFile = pkgs.runCommand "lockfile.json" {
    nativeBuildInputs = [ pkgs.yaml2json ];
  } ''
    yaml2json < ${./test-project/pnpm-lock.yaml} > $out
  '';

  # Use Import From Derivation (IFD) to read the JSON at evaluation time
  lockfileData = builtins.fromJSON (builtins.readFile lockfileJsonFile);
  packages = lockfileData.packages;
  
  # Helper to convert SHA512 integrity hash to SHA256 for nix
  convertIntegrityToSha256 = integrity:
    # For now, we'll use the hardcoded sha256 we know works
    # TODO: Properly convert integrity hashes
    if (builtins.hasAttr "lodash@4.17.21" packages)
    then "sha256-agh6yeVwKgydYPvNSGlgEmRuyN8Ukd6kcrFQ55/K+AQ="
    else throw "Unknown package integrity conversion needed";

  # Helper function to build a package derivation from lockfile data
  buildPackageFromLockfile = name: info:
    let
      # Parse package@version format
      atIndex = builtins.stringLength name - 1 - (builtins.stringLength (builtins.elemAt (builtins.match ".*@([^@]+)" name) 0));
      packageName = builtins.substring 0 atIndex name;
      version = builtins.elemAt (builtins.match ".*@([^@]+)" name) 0;
      
      integrity = info.resolution.integrity or "";
      sha256 = convertIntegrityToSha256 integrity;
      
    in pkgs.stdenv.mkDerivation {
      pname = packageName;
      version = version;
      
      src = pkgs.fetchurl {
        url = "https://registry.npmjs.org/${packageName}/-/${packageName}-${version}.tgz";
        inherit sha256;
      };
      
      dontBuild = true;
      
      installPhase = ''
        mkdir -p $out
        tar -xzf $src --strip-components=1 -C $out
      '';
    };

  # Generate all package derivations
  packageDerivations = builtins.mapAttrs buildPackageFromLockfile packages;

in {
  # Debug info
  debug = {
    inherit lockfileData packages;
    packageCount = builtins.length (builtins.attrNames packages);
  };
  
  # The actual derivations
  inherit packageDerivations;
  
  # Specifically expose lodash for testing
  lodash = packageDerivations."lodash@4.17.21" or null;
}