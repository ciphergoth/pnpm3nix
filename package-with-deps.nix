{ pkgs ? import <nixpkgs> {} }:

let
  # First build lodash (dependency)
  lodash = pkgs.stdenv.mkDerivation {
    pname = "lodash";
    version = "4.17.21";
    
    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/lodash/-/lodash-4.17.21.tgz";
      sha256 = "sha256-agh6yeVwKgydYPvNSGlgEmRuyN8Ukd6kcrFQ55/K+AQ=";
    };
    
    dontBuild = true;
    
    installPhase = ''
      mkdir -p $out
      tar -xzf $src --strip-components=1 -C $out
    '';
  };
  
  # Now build a mock package that depends on lodash  
  mockPackage = pkgs.stdenv.mkDerivation {
    pname = "mock-package";
    version = "1.0.0";
    
    # Create a fake package source
    src = pkgs.writeTextDir "package.json" (builtins.toJSON {
      name = "mock-package";
      version = "1.0.0";
      dependencies = {
        lodash = "^4.17.21";
      };
    });
    
    buildInputs = [ lodash ];
    
    dontBuild = true;
    
    installPhase = ''
      mkdir -p $out
      cp -r $src/* $out/
      
      # Create node_modules with symlink to lodash
      mkdir -p $out/node_modules
      ln -s ${lodash} $out/node_modules/lodash
      
      # Create a simple index.js that uses lodash
      cat > $out/index.js << EOF
const _ = require('lodash');

function testLodashImport() {
  const result = _.chunk([1,2,3,4], 2);
  return {
    success: true,
    message: 'Mock package loaded lodash successfully via symlink',
    chunkResult: result
  };
}

module.exports = { testLodashImport };
EOF
    '';
  };
  
in mockPackage