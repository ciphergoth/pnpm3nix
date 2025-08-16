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
  importers = lockfileData.importers;
  
  # Get the directory containing the lockfile for resolving workspace paths
  lockfileDir = builtins.dirOf lockfilePath;
  
  # Extract workspace packages from importers that have link: dependencies
  workspacePackages = builtins.listToAttrs (builtins.concatLists (builtins.attrValues (builtins.mapAttrs (importerPath: importerData:
    let
      deps = importerData.dependencies or {};
      linkDeps = builtins.filter (dep: 
        let depInfo = builtins.getAttr dep deps;
        in builtins.hasAttr "version" depInfo && builtins.substring 0 5 depInfo.version == "link:"
      ) (builtins.attrNames deps);
    in builtins.map (depName:
      let 
        depInfo = builtins.getAttr depName deps;
        linkPath = builtins.substring 5 (builtins.stringLength depInfo.version) depInfo.version; # Remove "link:" prefix
        workspacePath = "${lockfileDir}/${linkPath}";
      in {
        name = depName;
        value = {
          path = workspacePath;
          version = "workspace";
        };
      }
    ) linkDeps
  ) importers)));
  

  # Create entries for peer dependency contexts from snapshots
  peerContextPackages = builtins.mapAttrs (snapshotKey: snapshotData: 
    let
      # Check if this snapshot key has peer dependency context (contains parentheses)
      hasPeerContext = builtins.match ".*\\(.*\\)" snapshotKey != null;
    in if hasPeerContext then
      # For peer context packages, we need to find the base package info
      let
        # Extract base package name (everything before the first parenthesis)
        baseMatch = builtins.match "([^(]+)\\(.*\\)" snapshotKey;
        basePackageKey = builtins.elemAt baseMatch 0;
        basePackageInfo = builtins.getAttr basePackageKey packages;
      in basePackageInfo // { 
        isPeerContext = true; 
        snapshotKey = snapshotKey;
      }
    else null
  ) (builtins.removeAttrs snapshots (builtins.attrNames packages)); # Only consider snapshots not already in packages
  
  # Remove null entries from peerContextPackages
  validPeerContextPackages = builtins.removeAttrs peerContextPackages 
    (builtins.filter (key: (builtins.getAttr key peerContextPackages) == null) (builtins.attrNames peerContextPackages));

  # Combine npm packages, workspace packages, and peer context packages
  allPackages = packages // 
    (builtins.mapAttrs (name: wsInfo: {
      # Workspace packages don't have resolution info, we'll handle them specially
      isWorkspace = true;
      path = wsInfo.path;
    }) workspacePackages) //
    validPeerContextPackages;

  # Generate all package derivations using recursive set
  packageDerivations = pkgs.lib.fix (self: builtins.mapAttrs (name: info:
    if info.isWorkspace or false then
      # Handle workspace packages
      let
        workspaceInfo = builtins.getAttr name workspacePackages;
      in pkgs.stdenv.mkDerivation {
        pname = name;
        version = "workspace";
        
        src = workspaceInfo.path;
        
        dontBuild = true;
        
        installPhase = ''
          mkdir -p $out
          cp -r $src/* $out/
        '';
      }
    else if info.isPeerContext or false then
      # Handle peer context packages - they're the same as base packages but with different dependency contexts
      let
        # Parse the base package name from the snapshot key
        baseMatch = builtins.match "([^(]+)\\(.*\\)" name;
        basePackageKey = builtins.elemAt baseMatch 0;
        
        # Parse package@version format for the base package
        versionMatch = builtins.match ".*@([^@]+)" basePackageKey;
        version = builtins.elemAt versionMatch 0;
        atIndex = builtins.stringLength basePackageKey - 1 - (builtins.stringLength version);
        fullPackageName = builtins.substring 0 atIndex basePackageKey;
        
        # For scoped packages
        isScoped = builtins.substring 0 1 fullPackageName == "@";
        tarballName = if isScoped 
          then let scopeMatch = builtins.match "@([^/]+)/(.+)" fullPackageName;
               in builtins.elemAt scopeMatch 1
          else fullPackageName;
        
        integrity = info.resolution.integrity or "";
        
        # Get dependencies for this peer context from snapshots
        packageSnapshots = snapshots.${name} or {};
        packageDependencies = packageSnapshots.dependencies or {};
        
      in pkgs.stdenv.mkDerivation {
        pname = fullPackageName;
        version = version;
        
        src = pkgs.fetchurl {
          url = "https://registry.npmjs.org/${fullPackageName}/-/${tarballName}-${version}.tgz";
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
    else
      # Handle npm packages
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
  ) allPackages);

in {
  # Debug info
  debug = {
    inherit lockfileData packages workspacePackages;
    packageCount = builtins.length (builtins.attrNames packages);
    workspaceCount = builtins.length (builtins.attrNames workspacePackages);
  };
  
  # The actual derivations
  inherit packageDerivations;
}
