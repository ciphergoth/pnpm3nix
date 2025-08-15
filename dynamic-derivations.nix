{ pkgs ? import <nixpkgs> {} }:

lockfilePath:

let
  # Parse lockfile using yaml2json
  lockfileData = builtins.fromJSON (builtins.readFile (pkgs.runCommand "lockfile.json" {
    nativeBuildInputs = [ pkgs.yaml2json ];
    src = lockfilePath;
  } ''yaml2json < $src > $out''));
  
  packages = lockfileData.packages;
  snapshots = lockfileData.snapshots or {};
  

  # Generate all package derivations using recursive set
  packageDerivations = pkgs.lib.fix (self: builtins.mapAttrs (name: info:
    let
      # Parse package@version format, handling scoped packages
      versionMatch = builtins.match ".*@([^@]+)" name;
      version = builtins.elemAt versionMatch 0;
      atIndex = builtins.stringLength name - 1 - (builtins.stringLength version);
      fullPackageName = builtins.substring 0 atIndex name;
      
      # For scoped packages like @types/node, extract scope and package name
      isScoped = builtins.substring 0 1 fullPackageName == "@";
      scopeAndPackage = if isScoped 
        then builtins.match "@([^/]+)/(.+)" fullPackageName
        else null;
      
      packageName = fullPackageName;
      tarballName = if isScoped 
        then builtins.elemAt scopeAndPackage 1  # Just the package part for tarball
        else fullPackageName;
      
      integrity = info.resolution.integrity or "";
      
      # Get dependencies for this package from snapshots
      packageSnapshots = snapshots.${name} or {};
      packageDependencies = packageSnapshots.dependencies or {};
      
    in pkgs.stdenv.mkDerivation {
      pname = packageName;
      version = version;
      
      src = pkgs.fetchurl {
        url = "https://registry.npmjs.org/${packageName}/-/${tarballName}-${version}.tgz";
        hash = integrity;
      };
      
      dontBuild = true;
      
      installPhase = ''
        mkdir -p $out
        tar -xzf $src --strip-components=1 -C $out
        
        # Create node_modules with dependencies if any exist
        if [ ${toString (builtins.length (builtins.attrNames packageDependencies))} -gt 0 ]; then
          mkdir -p $out/node_modules
          ${builtins.concatStringsSep "\n" (builtins.attrValues (builtins.mapAttrs (depName: depVersion: 
            let 
              depKey = "${depName}@${depVersion}";
              depDerivation = builtins.getAttr depKey self;
            in "ln -s ${depDerivation} $out/node_modules/${depName}"
          ) packageDependencies))}
        fi
      '';
    }
  ) packages);

in {
  # Debug info
  debug = {
    inherit lockfileData packages;
    packageCount = builtins.length (builtins.attrNames packages);
  };
  
  # The actual derivations
  inherit packageDerivations;
}
