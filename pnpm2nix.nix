{ pkgs ? import <nixpkgs> {} }:

{
  mkPnpmPackage = { src, name ? null, version ? "1.0.0" }:
    let
      # Auto-detect lockfile path
      lockfilePath = src + "/pnpm-lock.yaml";
      
      # Import the dynamic derivation generator function
      pnpm2nixInternal = import ./dynamic-derivations.nix { inherit pkgs; };
      dynamicDerivations = pnpm2nixInternal lockfilePath;
      packageDerivations = dynamicDerivations.packageDerivations;
      
      # Get the project's direct dependencies from the lockfile
      lockfileData = dynamicDerivations.debug.lockfileData;
      projectDeps = lockfileData.importers.".".dependencies or {};
      projectDevDeps = lockfileData.importers.".".devDependencies or {};
      allProjectDeps = projectDeps // projectDevDeps;
      
      # Auto-detect project name from package.json if not provided
      packageJsonPath = src + "/package.json";
      packageJson = if builtins.pathExists packageJsonPath 
        then builtins.fromJSON (builtins.readFile packageJsonPath)
        else {};
      projectName = if name != null then name else (packageJson.name or "unknown");
      projectVersion = packageJson.version or version;
      
      # Create symlink commands for all dependencies, handling scoped packages and workspaces
      symlinkCommands = builtins.concatStringsSep "\n" (builtins.attrValues (builtins.mapAttrs (depName: depInfo: 
        let 
          # For workspace dependencies, use just the name; for npm packages, use name@version
          isWorkspace = builtins.substring 0 5 depInfo.version == "link:";
          depKey = if isWorkspace then depName else "${depName}@${depInfo.version}";
          depDerivation = builtins.getAttr depKey packageDerivations;
          isScoped = builtins.substring 0 1 depName == "@";
        in if isScoped 
          then 
            let scopeMatch = builtins.match "@([^/]+)/(.+)" depName;
                scope = builtins.elemAt scopeMatch 0;
                packageInScope = builtins.elemAt scopeMatch 1;
            in "mkdir -p $out/node_modules/@${scope} && ln -s ${depDerivation} $out/node_modules/@${scope}/${packageInScope}"
          else "ln -s ${depDerivation} $out/node_modules/${depName}"
      ) allProjectDeps));
      
    in pkgs.stdenv.mkDerivation {
      pname = projectName;
      version = projectVersion;
      
      inherit src;
      
      dontBuild = true;
      
      installPhase = ''
        mkdir -p $out
        cp -r $src/* $out/
        
        # Create node_modules with symlinks to all direct dependencies
        mkdir -p $out/node_modules
        
        # Link all dependencies
        ${symlinkCommands}
      '';
    };
}