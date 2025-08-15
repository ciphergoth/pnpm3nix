{ pkgs ? import <nixpkgs> {} }:

let
  # Parse lockfile using yaml2json
  lockfileData = builtins.fromJSON (builtins.readFile (pkgs.runCommand "lockfile.json" {
    nativeBuildInputs = [ pkgs.yaml2json ];
    src = ./test-project/pnpm-lock.yaml;
  } ''yaml2json < $src > $out''));
  
  packages = lockfileData.packages;
  

  # Helper function to build a package derivation from lockfile data
  buildPackageFromLockfile = name: info:
    let
      # Parse package@version format
      atIndex = builtins.stringLength name - 1 - (builtins.stringLength (builtins.elemAt (builtins.match ".*@([^@]+)" name) 0));
      packageName = builtins.substring 0 atIndex name;
      version = builtins.elemAt (builtins.match ".*@([^@]+)" name) 0;
      
      integrity = info.resolution.integrity or "";
      
    in pkgs.stdenv.mkDerivation {
      pname = packageName;
      version = version;
      
      src = pkgs.fetchurl {
        url = "https://registry.npmjs.org/${packageName}/-/${packageName}-${version}.tgz";
        hash = integrity;
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
}
