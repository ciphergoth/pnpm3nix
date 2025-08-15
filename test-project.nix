{ pkgs ? import <nixpkgs> {} }:

let
  # Import the dynamic derivation generator function
  pnpm2nix = import ./dynamic-derivations.nix { inherit pkgs; };
  dynamicDerivations = pnpm2nix ./test-project/pnpm-lock.yaml;
  packageDerivations = dynamicDerivations.packageDerivations;
  
  # Get the project's direct dependencies from the lockfile
  lockfileData = dynamicDerivations.debug.lockfileData;
  projectDeps = lockfileData.importers.".".dependencies or {};
  projectDevDeps = lockfileData.importers.".".devDependencies or {};
  allProjectDeps = projectDeps // projectDevDeps;
  
  # Create symlink commands for all dependencies, handling scoped packages
  symlinkCommands = builtins.concatStringsSep "\n" (builtins.attrValues (builtins.mapAttrs (depName: depInfo: 
    let 
      depKey = "${depName}@${depInfo.version}";
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
  
  # Build the test project with proper node_modules structure
  testProject = pkgs.stdenv.mkDerivation {
    pname = "test-project";
    version = "1.0.0";
    
    src = ./test-project;
    
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

in testProject