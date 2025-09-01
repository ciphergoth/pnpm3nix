{ pkgs ? import <nixpkgs> {}, tarjanCli ? (import ./tarjan-cli.nix { inherit pkgs; }) }:

{
  mkPnpmPackage = { workspace, component, name ? null, version ? "1.0.0", script ? "build", buildInputs ? [] }:
    let
      src = workspace + "/${component}";
      
      # Auto-detect lockfile path from workspace root
      lockfilePath = workspace + "/pnpm-lock.yaml";
      
      # Import the derivation generator function
      derivations = import ./derivations.nix { inherit pkgs tarjanCli; } lockfilePath;
      packageDerivations = derivations.packageDerivations;
      
      # Get the specific component's dependencies from the lockfile
      lockfileData = derivations.debug.lockfileData;
      componentImporter = lockfileData.importers.${component} or lockfileData.importers.".";
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
      
      # Create symlink commands for dependencies
      createSymlinkCommands = deps: targetDir: builtins.concatStringsSep "\n" (builtins.attrValues (builtins.mapAttrs (depName: depInfo: 
        let 
          # For workspace dependencies, use just the name; for npm packages, use name@version
          isWorkspace = builtins.substring 0 5 depInfo.version == "link:";
          depKey = if isWorkspace then depName else "${depName}@${depInfo.version}";
          
          # Look up dependency directly in package derivations
          resolvedDep = if builtins.hasAttr depKey packageDerivations then
            let 
              packageDerivation = builtins.getAttr depKey packageDerivations;
              safePkgName = derivations.makeSafePkgName depKey;
            in "${packageDerivation}/${safePkgName}"
          else
            throw "Dependency ${depKey} not found in package derivations";
          
        in derivations.makeSymlinkCommand depName resolvedDep targetDir
      ) deps));
      
      # Build-time: all dependencies (runtime + dev)
      buildTimeSymlinks = createSymlinkCommands allProjectDeps "node_modules";
      
      # Create .bin symlink commands for build-time executables
      createBinSymlinks = deps: targetDir: builtins.concatStringsSep "\n" (builtins.concatLists (builtins.attrValues (builtins.mapAttrs (depName: depInfo:
        let 
          isWorkspace = builtins.substring 0 5 depInfo.version == "link:";
          depKey = if isWorkspace then depName else "${depName}@${depInfo.version}";
          
          resolvedDep = if builtins.hasAttr depKey packageDerivations then
            let 
              packageDerivation = builtins.getAttr depKey packageDerivations;
              safePkgName = derivations.makeSafePkgName depKey;
            in "${packageDerivation}/${safePkgName}"
          else "";
          
        in if resolvedDep != "" then
          let binEntries = derivations.extractBinInfo resolvedDep depName;
          in builtins.map (binEntry: 
            "ln -sf \"../${depName}/${binEntry.path}\" \"${targetDir}/.bin/${binEntry.name}\""
          ) binEntries
        else []
      ) deps)));
      
      buildTimeBinSymlinks = createBinSymlinks allProjectDeps "node_modules";
      
      # Runtime: only runtime dependencies  
      runtimeSymlinks = createSymlinkCommands projectDeps "$out/node_modules";
      runtimeBinSymlinks = createBinSymlinks projectDeps "$out/node_modules";
      
      # Create build script command
      buildCommand = if script != "" then "npm run ${script}" else "";
      
    in pkgs.stdenv.mkDerivation {
      pname = projectName;
      version = projectVersion;
      
      inherit src;
      
      buildInputs = [ pkgs.nodejs ] ++ buildInputs;
      
      configurePhase = ''
        runHook preConfigure
        
        # Clean any existing node_modules from source
        rm -rf node_modules
        mkdir -p node_modules
        ${buildTimeSymlinks}
        
        # Create .bin directory with symlinks to executable scripts
        mkdir -p node_modules/.bin
        ${buildTimeBinSymlinks}
        
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
        
        # Create .bin directory for runtime
        mkdir -p $out/node_modules/.bin
        ${runtimeBinSymlinks}
      '';
    };
}