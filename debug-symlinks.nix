{ pkgs ? import <nixpkgs> {} }:

let
  sccAware = import ./scc-aware-derivations.nix { inherit pkgs; };
  sccDerivations = sccAware ./test-project/pnpm-lock.yaml;
  bundleDerivations = sccDerivations.packageDerivations;
  packageToBundle = sccDerivations.debug.packageToBundle;
  
  # Get utils dependencies
  lockfileData = sccDerivations.debug.lockfileData;
  utilsDeps = lockfileData.importers."packages/utils".dependencies or {};
  
  # Create symlink commands like in the main API
  createSymlinkCommands = deps: targetDir: builtins.concatStringsSep "\n" (builtins.attrValues (builtins.mapAttrs (depName: depInfo: 
    let 
      # For workspace dependencies, use just the name; for npm packages, use name@version
      isWorkspace = builtins.substring 0 5 depInfo.version == "link:";
      depKey = if isWorkspace then depName else "${depName}@${depInfo.version}";
      
      # Look up dependency in bundle structure
      resolvedDep = if builtins.hasAttr depKey packageToBundle then
        let 
          bundleName = builtins.getAttr depKey packageToBundle;
          bundleDerivation = builtins.getAttr bundleName bundleDerivations;
          safePkgName = sccDerivations.makeSafePkgName depKey;
        in "${bundleDerivation}/${safePkgName}"
      else
        throw "Dependency ${depKey} not found in bundle derivations";
      
      # Handle scoped package directory creation
      isScoped = builtins.substring 0 1 depName == "@";
    in if isScoped 
      then 
        let scopeMatch = builtins.match "@([^/]+)/(.+)" depName;
            scope = builtins.elemAt scopeMatch 0;
            packageInScope = builtins.elemAt scopeMatch 1;
        in "mkdir -p ${targetDir}/@${scope} && ln -s ${resolvedDep} ${targetDir}/@${scope}/${packageInScope}"
      else "ln -s ${resolvedDep} ${targetDir}/${depName}"
  ) deps));
  
  symlinkCommands = createSymlinkCommands utilsDeps "node_modules";

in pkgs.writeText "symlink-commands" symlinkCommands