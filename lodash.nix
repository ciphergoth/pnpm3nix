{ pkgs ? import <nixpkgs> {} }:

pkgs.stdenv.mkDerivation {
  pname = "lodash";
  version = "4.17.21";
  
  src = pkgs.fetchurl {
    url = "https://registry.npmjs.org/lodash/-/lodash-4.17.21.tgz";
    sha256 = "sha256-agh6yeVwKgydYPvNSGlgEmRuyN8Ukd6kcrFQ55/K+AQ=";
  };
  
  dontBuild = true;
  
  installPhase = ''
    # Extract the tarball and copy to output
    mkdir -p $out
    tar -xzf $src --strip-components=1 -C $out
    
    # Ensure package.json is present
    if [ ! -f "$out/package.json" ]; then
      echo "Error: package.json not found in lodash package"
      exit 1
    fi
  '';
  
  meta = with pkgs.lib; {
    description = "A modern JavaScript utility library";
    homepage = "https://lodash.com";
    license = licenses.mit;
  };
}