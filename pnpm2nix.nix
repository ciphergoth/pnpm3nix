{ pkgs ? import <nixpkgs> {} }:

{
  mkPnpmPackage = { workspace, components, name ? null, version ? "1.0.0", buildScripts ? [] }:
    let
      # For now, handle single component (first in array)
      componentPath = builtins.head components;
      src = workspace + "/${componentPath}";
      
      # Auto-detect lockfile path from workspace root
      lockfilePath = workspace + "/pnpm-lock.yaml";
      
      # Import the dynamic derivation generator function
      pnpm2nixInternal = import ./dynamic-derivations.nix { inherit pkgs; };
      dynamicDerivations = pnpm2nixInternal lockfilePath;
      packageDerivations = dynamicDerivations.packageDerivations;
      
      # Get the specific component's dependencies from the lockfile
      lockfileData = dynamicDerivations.debug.lockfileData;
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
      
      # Create symlink commands for dependencies
      createSymlinkCommands = deps: targetDir: builtins.concatStringsSep "\n" (builtins.attrValues (builtins.mapAttrs (depName: depInfo: 
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
            in "mkdir -p ${targetDir}/@${scope} && ln -s ${depDerivation} ${targetDir}/@${scope}/${packageInScope}"
          else "ln -s ${depDerivation} ${targetDir}/${depName}"
      ) deps));
      
      # Build-time: all dependencies (runtime + dev)
      buildTimeSymlinks = createSymlinkCommands allProjectDeps "node_modules";
      
      # Runtime: only runtime dependencies  
      runtimeSymlinks = createSymlinkCommands projectDeps "$out/node_modules";
      
      # Create build script commands
      buildCommands = builtins.concatStringsSep "\n" (builtins.map (script: 
        "npm run ${script}"
      ) buildScripts);
      
    in pkgs.stdenv.mkDerivation {
      pname = projectName;
      version = projectVersion;
      
      inherit src;
      
      buildInputs = [ pkgs.nodejs ];
      
      
      configurePhase = ''
        runHook preConfigure
        
        mkdir -p node_modules
        ${buildTimeSymlinks}
        
        # Create .bin directory with symlinks to executable scripts
        mkdir -p node_modules/.bin
        for dep in node_modules/*; do
          if [ -d "$dep/bin" ]; then
            for bin in "$dep"/bin/*; do
              if [ -f "$bin" ]; then
                ln -sf "../$(basename "$dep")/bin/$(basename "$bin")" "node_modules/.bin/$(basename "$bin")"
              fi
            done
          fi
        done
        
        export PATH="$PWD/node_modules/.bin:$PATH"
        
        runHook postConfigure
      '';
      
      buildPhase = ''
        ${buildCommands}
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