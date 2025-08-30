#!/usr/bin/env bash

set -euo pipefail

echo "🔧 Building TypeScript webapp with SCC-aware approach (includes pg circular dependency)..."
nix-build -E '
  let pkgs = import <nixpkgs> {};
      pnpm2nixSCC = import ./pnpm2nix-scc.nix { 
        inherit pkgs; 
        tarjanPath = "/Users/paul/g/zerbongle/tarjan/target/debug/tarjan-cli";
      };
  in pnpm2nixSCC.mkPnpmPackage {
    workspace = ./test-project;
    components = ["apps/ts-webapp"];
    script = "build";
  }
'

echo "🧪 Testing TypeScript compilation with circular dependencies..."
nix-shell --run "cd result && node dist/index.js"

echo "✅ SCC-aware build with circular dependencies completed successfully!"