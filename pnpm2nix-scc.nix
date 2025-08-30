{ pkgs ? import <nixpkgs> {}, tarjanCli ? (import ./tarjan-cli.nix { inherit pkgs; }) }:

{
  mkPnpmPackage = { workspace, components, name ? null, version ? "1.0.0", script ? "build" }:
    let
      # For now, handle single component (first in array)
      componentPath = builtins.head components;
      src = workspace + "/${componentPath}";
      
      # Auto-detect lockfile path from workspace root
      lockfilePath = workspace + "/pnpm-lock.yaml";
      
      # Import the SCC-aware derivation generator function
      sccAwareInternal = import ./scc-aware-derivations.nix { inherit pkgs tarjanCli; };
      sccDerivations = sccAwareInternal lockfilePath;
      bundleDerivations = sccDerivations.packageDerivations;
      packageToBundle = sccDerivations.debug.packageToBundle;
      
      # Get the specific component's dependencies from the lockfile
      lockfileData = sccDerivations.debug.lockfileData;
      componentImporter = lockfileData.importers.${componentPath} or lockfileData.importers.".";
      projectDeps = componentImporter.dependencies or {};
      projectDevDeps = componentImporter.devDependencies or {};
      allProjectDeps = projectDeps // projectDevDeps;
      
      # Auto-detect project name from component's package.json if not provided
      packageJsonPath = src + "/package.json";
      packageJson = if builtins.pathExists packageJsonPath 
        then builtins.fromJSON (builtins.readFile packageJsonPath)
        else {};
      projectName = if name != null then name else (packageJson.name or "unknown");
      projectVersion = packageJson.version or version;
      
      # Create symlink commands for dependencies using SCC-aware resolution
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
            in "mkdir -p ${targetDir}/@${scope}; ln -s ${resolvedDep} ${targetDir}/@${scope}/${packageInScope}"
          else "ln -s ${resolvedDep} ${targetDir}/${depName}"
      ) deps));
      
      # Build-time: all dependencies (runtime + dev)
      buildTimeSymlinks = createSymlinkCommands allProjectDeps "node_modules";
      
      # Runtime: only runtime dependencies  
      runtimeSymlinks = createSymlinkCommands projectDeps "$out/node_modules";
      
      # Create build script command
      buildCommand = if script != "" then "npm run ${script}" else "";
      
    in pkgs.stdenv.mkDerivation {
      pname = projectName;
      version = projectVersion;
      
      inherit src;
      
      buildInputs = [ pkgs.nodejs ];
      
      
      configurePhase = ''
        runHook preConfigure
        
        # Clean any existing node_modules from source
        rm -rf node_modules
        mkdir -p node_modules
        ${buildTimeSymlinks}
        
        # Create .bin directory with symlinks to executable scripts
        mkdir -p node_modules/.bin
        for bundle_dir in node_modules/*; do
          if [ -d "$bundle_dir" ] && [ -L "$bundle_dir" ]; then
            # Follow the symlink to the actual bundle/package directory
            actual_dir=$(readlink "$bundle_dir")
            if [ -d "$actual_dir/bin" ]; then
              for bin in "$actual_dir"/bin/*; do
                if [ -f "$bin" ]; then
                  ln -sf "../$(basename "$bundle_dir")/bin/$(basename "$bin")" "node_modules/.bin/$(basename "$bin")"
                fi
              done
            fi
          fi
        done
        
        export PATH="$PWD/node_modules/.bin:$PATH"
        
        runHook postConfigure
      '';
      
      buildPhase = ''
        ${buildCommand}
        rm -rf node_modules
      '';
      
      installPhase = ''
        mkdir -p $out
        cp -r --no-preserve=ownership . $out/
        mkdir -p $out/node_modules
        ${runtimeSymlinks}
      '';
    };
}