{ pkgs ? import <nixpkgs> {} }:

let
  # Import the dynamic derivation generator
  dynamicDerivations = import ./dynamic-derivations.nix { inherit pkgs; };
  packageDerivations = dynamicDerivations.packageDerivations;
  
  # Build the test project with proper node_modules structure
  testProject = pkgs.stdenv.mkDerivation {
    pname = "test-project";
    version = "1.0.0";
    
    src = ./test-project;
    
    dontBuild = true;
    
    installPhase = ''
      mkdir -p $out
      cp -r $src/* $out/
      
      # Create node_modules with symlinks to all dependencies
      mkdir -p $out/node_modules
      
      # Link lodash from our generated derivations
      ln -s ${packageDerivations."lodash@4.17.21"} $out/node_modules/lodash
    '';
  };

in testProject