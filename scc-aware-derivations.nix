{ pkgs ? import <nixpkgs> {}, tarjanCli ? (import ./tarjan-cli.nix { inherit pkgs; }) }:

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

  # === SCC DETECTION PHASE ===
  
  # Run streamlined pipeline: yaml2json | jq | tarjan-cli
  sccs = builtins.fromJSON (builtins.readFile (pkgs.runCommand "tarjan-sccs" {
    nativeBuildInputs = [ pkgs.yaml2json pkgs.jq tarjanCli ];
  } ''
    # Streamlined pipeline: lockfile -> dependency graph -> SCCs
    yaml2json < ${lockfilePath} | jq '
      # Extract dependency graph from snapshots with proper name@version format
      (.snapshots // {}) | to_entries | map({
        key: .key,
        value: (.value.dependencies // {}) | to_entries | map(.key + "@" + .value)
      }) | from_entries
    ' | tarjan-cli > $out
  ''));
  
  # Generate semantic bundle names
  generateBundleName = sccPackages:
    let 
      packageCount = builtins.length sccPackages;
      sortedPackages = builtins.sort (a: b: a < b) sccPackages;
      
      # Extract clean package name (remove version and peer context)
      extractPackageName = pkg:
        let match = builtins.match "([^@]+).*" pkg;
        in if match != null then builtins.elemAt match 0 else pkg;
        
    in
      if packageCount == 1 then
        "${extractPackageName (builtins.head sortedPackages)}-bundle"
      else if packageCount <= 3 then
        let
          cleanNames = builtins.map extractPackageName sortedPackages;
          uniqueNames = builtins.sort (a: b: a < b) (pkgs.lib.unique cleanNames);
        in "${builtins.concatStringsSep "-" uniqueNames}-cycle-bundle"
      else
        # For large cycles, use first package + hash
        let 
          firstPackage = builtins.head sortedPackages;
          cleanName = extractPackageName firstPackage;
          sccHash = builtins.hashString "md5" (builtins.toJSON sortedPackages);
          shortHash = builtins.substring 0 8 sccHash;
        in "${cleanName}-cycle-${shortHash}-bundle";
  
  # Create bundle info for all SCCs (both singletons and cycles)
  sccBundles = builtins.listToAttrs (builtins.genList (sccIndex:
    let 
      sccPackages = builtins.elemAt sccs sccIndex;
      bundleName = generateBundleName sccPackages;
    in {
      name = bundleName;
      value = {
        index = sccIndex;
        packages = sccPackages;
        isCyclic = builtins.length sccPackages > 1;
      };
    }
  ) (builtins.length sccs));
  
  # Helper function for consistent safe name generation
  makeSafePkgName = pkg:
    let rawSafeName = builtins.replaceStrings ["@" "/" "(" ")"] ["-" "-" "-" "-"] pkg;
        len = builtins.stringLength rawSafeName;
    in if len > 0 && builtins.substring (len - 1) 1 rawSafeName == "-" 
       then builtins.substring 0 (len - 1) rawSafeName
       else rawSafeName;

  # Map each package to its bundle name
  packageToBundle = builtins.listToAttrs (builtins.concatLists (
    builtins.attrValues (builtins.mapAttrs (bundleName: bundleInfo:
      builtins.map (pkg: {
        name = pkg;
        value = bundleName;
      }) bundleInfo.packages
    ) sccBundles)
  ));

  # === DERIVATION GENERATION ===

  # Function to create a bundle derivation (handles both singletons and cycles)
  mkBundleDerivation = bundleName: bundleInfo: allDerivations:
    let
      sccPackages = bundleInfo.packages;
      isCyclic = bundleInfo.isCyclic;
      
      # Get package info for all packages in this bundle
      bundlePackageInfos = builtins.map (pkg: {
        name = pkg;
        info = if builtins.hasAttr pkg allPackages then
          builtins.getAttr pkg allPackages
        else
          throw "Package ${pkg} not found in allPackages";
      }) sccPackages;
      
      # Helper to extract package sources
      extractPackageSources = builtins.concatStringsSep "\n" (builtins.map (pkgEntry:
        let 
          pkg = pkgEntry.name;
          pkgInfo = pkgEntry.info;
          
          # Handle workspace packages differently
          isWorkspacePackage = pkgInfo.isWorkspace or false;
          
        in if isWorkspacePackage then
          # For workspace packages, copy from local path
          let workspaceInfo = builtins.getAttr pkg workspacePackages;
          in ''
            # Extract workspace package ${pkg}
            mkdir -p temp-${makeSafePkgName pkg}
            cp -r ${workspaceInfo.path}/* temp-${makeSafePkgName pkg}/
          ''
        else
          # For npm packages, extract from tarball
          let
            # Parse package details - for URLs, always use base package name without peer context
            packageKey = if (pkgInfo.isPeerContext or false) then pkgInfo.snapshotKey else pkg;
            
            # Remove peer context: "react-dom@18.3.1(react@18.3.1)" -> "react-dom@18.3.1"
            basePackageKey = builtins.head (builtins.split "\\(" packageKey);
            
            # Extract version and name using regex
            # Pattern: capture everything before the last @ as name, everything after as version
            packageMatch = builtins.match "(.*)@([^@]+)" basePackageKey;
            
            fullPackageName = if packageMatch != null 
              then builtins.elemAt packageMatch 0
              else basePackageKey;
              
            version = if packageMatch != null
              then builtins.elemAt packageMatch 1
              else "unknown";
            
            isScoped = builtins.substring 0 1 fullPackageName == "@";
            tarballName = if isScoped 
              then let scopeMatch = builtins.match "@([^/]+)/(.+)" fullPackageName;
                   in if scopeMatch != null then builtins.elemAt scopeMatch 1 else fullPackageName
              else fullPackageName;
            
            integrity = pkgInfo.resolution.integrity or "";
            safePkgName = makeSafePkgName pkg;
            
          in ''
            # Extract npm package ${pkg}
            mkdir -p temp-${safePkgName}
            tar -xzf ${pkgs.fetchurl {
              url = "https://registry.npmjs.org/${fullPackageName}/-/${tarballName}-${version}.tgz";
              hash = integrity;
            }} --strip-components=1 -C temp-${safePkgName}
          ''
      ) bundlePackageInfos);
      
      # Helper to create symlinks (both internal and external)
      createSymlinks = builtins.concatStringsSep "\n" (builtins.concatLists (builtins.map (pkgEntry:
        let 
          pkg = pkgEntry.name;
          pkgInfo = pkgEntry.info;
          safePkgName = makeSafePkgName pkg;
          
          # Get dependencies
          packageKey = if (pkgInfo.isPeerContext or false) then pkgInfo.snapshotKey else pkg;
          packageSnapshots = snapshots.${packageKey} or {};
          packageDependencies = packageSnapshots.dependencies or {};
          
        in builtins.attrValues (builtins.mapAttrs (depName: depVersion:
          let 
            depKey = "${depName}@${depVersion}";
            isScoped = builtins.substring 0 1 depName == "@";
            
            # Helper to create scoped or regular symlink
            createSymlink = source: target:
              if isScoped then
                let scopeMatch = builtins.match "@([^/]+)/(.+)" depName;
                    scope = builtins.elemAt scopeMatch 0;
                    packageInScope = builtins.elemAt scopeMatch 1;
                in "mkdir -p ${target}/@${scope}; ln -sf ${source} ${target}/@${scope}/${packageInScope}"
              else "ln -sf ${source} ${target}/${depName}";
              
          in if builtins.elem depKey sccPackages then
            # Internal bundle dependency - relative symlink 
            let 
              safePkgDepName = makeSafePkgName depKey;
              # Count slashes in depName to determine path depth
              slashCount = builtins.length (builtins.filter (c: c == "/") (pkgs.lib.stringToCharacters depName));
              # Base depth is 2 (package/node_modules), plus one for each slash in depName
              upLevels = 2 + slashCount;
              relativePath = builtins.concatStringsSep "" (builtins.genList (_: "../") upLevels);
            in createSymlink "${relativePath}${safePkgDepName}" "$out/${safePkgName}/node_modules"
          else if builtins.hasAttr depKey packageToBundle then
            # External dependency in another bundle
            let 
              depBundleName = builtins.getAttr depKey packageToBundle;
              depBundleDrv = builtins.getAttr depBundleName allDerivations;
              safeDepName = makeSafePkgName depKey;
            in createSymlink "${depBundleDrv}/${safeDepName}" "$out/${safePkgName}/node_modules"
          else
            # Dependency not found - this shouldn't happen but provide fallback
            "echo 'Warning: Dependency ${depKey} not found for ${pkg}'"
        ) packageDependencies)
      ) bundlePackageInfos));
      
    in pkgs.stdenv.mkDerivation {
      name = bundleName;
      
      dontUnpack = true;
      dontBuild = true;
      
      installPhase = ''
        ${extractPackageSources}
        
        # Copy all packages to output with consistent structure
        ${builtins.concatStringsSep "\n" (builtins.map (pkgEntry:
          let 
            pkg = pkgEntry.name;
            safePkgName = makeSafePkgName pkg;
          in ''
            mkdir -p $out/${safePkgName}
            cp -r temp-${safePkgName}/* $out/${safePkgName}/
            mkdir -p $out/${safePkgName}/node_modules
          ''
        ) bundlePackageInfos)}
        
        # Create dependency symlinks
        ${createSymlinks}
      '';
    };

  # Generate all bundle derivations using recursive set
  packageDerivations = pkgs.lib.fix (self: 
    builtins.mapAttrs (bundleName: bundleInfo:
      mkBundleDerivation bundleName bundleInfo self
    ) sccBundles
  );

in {
  # Debug info
  debug = {
    inherit lockfileData packages workspacePackages sccs sccBundles packageToBundle;
    bundleCount = builtins.length (builtins.attrNames sccBundles);
    cyclicBundles = builtins.filter (bundle: bundle.isCyclic) (builtins.attrValues sccBundles);
  };
  
  # The actual derivations
  inherit packageDerivations;
  
  # Helper functions
  inherit makeSafePkgName;
}